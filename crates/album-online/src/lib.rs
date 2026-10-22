//! Looks albums up in online databases (MusicBrainz, Bangumi and the
//! CueTools database) to fill in their title, artist, release date, catalog
//! number, event and cover.

mod bangumi;
mod ctdb;
pub mod discid;
mod musicbrainz;

use album_formats::riplog;
use album_model::{Album, MatchKind, OnlineMatch, OnlineResults, OnlineSource};
use anyhow::{bail, Result};
use discid::Toc;
use std::collections::HashSet;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;
use std::time::Duration;

/// Shared client; the services ask clients to identify themselves.
pub(crate) static AGENT: LazyLock<ureq::Agent> = LazyLock::new(|| {
    ureq::AgentBuilder::new()
        .user_agent(concat!(
            "AlbumManager/",
            env!("CARGO_PKG_VERSION"),
            " ( https://github.com/Shizuku-in/AlbumManager )"
        ))
        .timeout(Duration::from_secs(20))
        .build()
});

/// Tables of contents of the album's discs: from rip logs, else from
/// single-file cue images.
fn tocs(album: &Album) -> Vec<Toc> {
    let from_logs: Vec<Toc> = album
        .logs
        .iter()
        .filter_map(|l| Toc::from_log(&riplog::read(Path::new(&l.path)).ok()?.text))
        .collect();
    if !from_logs.is_empty() {
        return from_logs;
    }
    album
        .discs
        .iter()
        .filter(|d| d.cue_path.is_some() && d.tracks.len() > 1)
        .filter(|d| d.tracks.iter().all(|t| t.file == d.tracks[0].file))
        .filter_map(|d| {
            let starts: Option<Vec<f64>> = d.tracks.iter().map(|t| t.start_secs).collect();
            let last = d.tracks.last()?;
            Toc::from_image(&starts?, last.start_secs? + last.duration_secs)
        })
        .collect()
}

/// The catalog number with case, spaces and dashes ignored.
fn catalog_key(s: &str) -> String {
    s.chars()
        .filter(|c| c.is_alphanumeric())
        .flat_map(char::to_uppercase)
        .collect()
}

/// MusicBrainz: by disc (rip log or cue image), catalog number, then title
/// and artist. Requests are throttled, so they run one after another.
fn musicbrainz(album: &Album, tocs: &[Toc]) -> Result<Vec<OnlineMatch>> {
    let s = &album.summary;
    let mut found = Vec::new();
    let mut error = None;
    let mut add = |r: Result<Vec<OnlineMatch>>, found: &mut Vec<OnlineMatch>| match r {
        Ok(v) => found.extend(v),
        Err(e) => error = Some(e),
    };
    for toc in tocs.iter().take(3) {
        add(musicbrainz::by_toc(toc), &mut found);
    }
    if let Some(catalog) = &s.catalog {
        // "SVWC-70501~2": the first disc's number.
        let first = catalog.split(['~', '～']).next().unwrap_or(catalog).trim();
        add(musicbrainz::by_catalog(first), &mut found);
    }
    if found.len() < 5 {
        add(
            musicbrainz::by_title(&s.title, s.artist.as_deref()),
            &mut found,
        );
        if s.artist.is_some() && found.len() < 3 {
            add(musicbrainz::by_title(&s.title, None), &mut found);
        }
    }
    match error {
        Some(e) if found.is_empty() => Err(e),
        _ => Ok(found),
    }
}

fn ctdb(tocs: &[Toc]) -> Result<Vec<OnlineMatch>> {
    let mut found = Vec::new();
    for toc in tocs.iter().take(3) {
        found.extend(ctdb::by_toc(toc)?);
    }
    Ok(found)
}

/// Releases on the given `sources` that may be `album`, best matches first:
/// same disc, similar disc, same catalog number, then by title. The sources
/// are queried in parallel; one failing doesn't fail the others.
pub fn lookup(album: &Album, sources: &[OnlineSource]) -> OnlineResults {
    let tocs = tocs(album);
    let catalog = album.summary.catalog.as_deref().map(catalog_key);
    let results: Vec<(OnlineSource, Result<Vec<OnlineMatch>>)> = std::thread::scope(|scope| {
        let jobs: Vec<_> = sources
            .iter()
            .map(|&src| {
                let tocs = &tocs;
                let job = scope.spawn(move || match src {
                    OnlineSource::MusicBrainz => musicbrainz(album, tocs),
                    OnlineSource::Bangumi => bangumi::search(&album.summary.title),
                    OnlineSource::Ctdb => ctdb(tocs),
                });
                (src, job)
            })
            .collect();
        jobs.into_iter()
            .map(|(src, job)| {
                let r = job
                    .join()
                    .unwrap_or_else(|_| Err(anyhow::anyhow!("panicked")));
                (src, r)
            })
            .collect()
    });
    let mut matches = Vec::new();
    let mut errors = Vec::new();
    for (src, r) in results {
        match r {
            Ok(v) => matches.extend(v),
            Err(e) => {
                let name = match src {
                    OnlineSource::MusicBrainz => "MusicBrainz",
                    OnlineSource::Bangumi => "Bangumi",
                    OnlineSource::Ctdb => "CueTools 数据库",
                };
                errors.push(format!("{name}：{e}"));
            }
        }
    }
    // A title hit with the album's catalog number is a catalog match.
    for m in &mut matches {
        if m.matched_by == MatchKind::Title
            && catalog.is_some()
            && m.catalog.as_deref().map(catalog_key) == catalog
        {
            m.matched_by = MatchKind::Catalog;
        }
    }
    let rank = |k: MatchKind| match k {
        MatchKind::DiscId => 0,
        MatchKind::Toc => 1,
        MatchKind::Catalog => 2,
        MatchKind::Title => 3,
    };
    matches.sort_by_key(|m| (rank(m.matched_by), -m.score));
    let mut seen = HashSet::new();
    matches.retain(|m| seen.insert((m.source.clone(), m.id.clone())));
    OnlineResults { matches, errors }
}

/// Downloads a cover into `dir` as `cover.jpg` (or `.png`), never
/// overwriting a file, and returns its path.
pub fn save_cover(url: &str, dir: &Path) -> Result<PathBuf> {
    let res = AGENT.get(url).call()?;
    let ext = match res.content_type() {
        "image/png" => "png",
        "image/jpeg" => "jpg",
        other => bail!("not an image: {other}"),
    };
    let mut bytes = Vec::new();
    res.into_reader().take(64 << 20).read_to_end(&mut bytes)?;
    let path = (1..)
        .map(|n| match n {
            1 => dir.join(format!("cover.{ext}")),
            n => dir.join(format!("cover ({n}).{ext}")),
        })
        .find(|p| !p.exists())
        .unwrap();
    std::fs::write(&path, bytes)?;
    Ok(path)
}
