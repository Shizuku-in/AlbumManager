//! Looks albums up in online databases (MusicBrainz for now) to fill in
//! their title, artist, release date, catalog number and cover.

pub mod discid;
mod musicbrainz;

use album_formats::riplog;
use album_model::{Album, MatchKind, OnlineMatch};
use anyhow::{bail, Result};
use discid::Toc;
use std::collections::HashSet;
use std::io::Read;
use std::path::{Path, PathBuf};

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

/// Releases that may be `album`, best matches first: same disc (from the
/// rip log or cue image), then catalog number, then title and artist.
pub fn lookup(album: &Album) -> Result<Vec<OnlineMatch>> {
    let s = &album.summary;
    let mut found = Vec::new();
    let mut errors = Vec::new();
    let mut add = |r: Result<Vec<OnlineMatch>>, found: &mut Vec<OnlineMatch>| match r {
        Ok(v) => found.extend(v),
        Err(e) => errors.push(e),
    };
    for toc in tocs(album).iter().take(3) {
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
    if found.is_empty() {
        if let Some(e) = errors.into_iter().next() {
            return Err(e);
        }
    }
    let rank = |k: MatchKind| match k {
        MatchKind::DiscId => 0,
        MatchKind::Toc => 1,
        MatchKind::Catalog => 2,
        MatchKind::Title => 3,
    };
    found.sort_by_key(|m| (rank(m.matched_by), -m.score));
    let mut seen = HashSet::new();
    found.retain(|m| seen.insert(m.id.clone()));
    Ok(found)
}

/// Downloads a cover into `dir` as `cover.jpg` (or `.png`), never
/// overwriting a file, and returns its path.
pub fn save_cover(url: &str, dir: &Path) -> Result<PathBuf> {
    let res = musicbrainz::AGENT.get(url).call()?;
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
