//! Looks albums up in online databases (MusicBrainz, Bangumi and the
//! CueTools database) to fill in their title, artist, release date, catalog
//! number, event and cover.

mod bangumi;
mod ctdb;
pub mod discid;
mod musicbrainz;

use album_formats::riplog;
use album_model::{Album, MatchKind, OnlineMatch, OnlineOptions, OnlineResults, OnlineSource};
use anyhow::{anyhow, bail, Result};
use discid::Toc;
use std::collections::HashSet;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::Duration;

/// HTTP client per the user's options; the services ask clients to identify
/// themselves.
fn agent(opts: &OnlineOptions) -> Result<ureq::Agent> {
    let mut b = ureq::AgentBuilder::new()
        .user_agent(concat!(
            "AlbumManager/",
            env!("CARGO_PKG_VERSION"),
            " ( https://github.com/Shizuku-in/AlbumManager )"
        ))
        .timeout(Duration::from_secs(opts.timeout_secs.clamp(5, 120).into()));
    if let Some(p) = opts
        .proxy
        .as_deref()
        .map(str::trim)
        .filter(|p| !p.is_empty())
    {
        b = b.proxy(ureq::Proxy::new(p).map_err(|_| anyhow!("代理地址无效：{p}"))?);
    }
    Ok(b.build())
}

/// A short reason a request failed, for the UI.
fn describe(e: &anyhow::Error) -> String {
    match e.downcast_ref::<ureq::Error>() {
        Some(ureq::Error::Status(503, _)) => "服务器繁忙（503），请稍后再试".into(),
        Some(ureq::Error::Status(code, _)) => format!("服务器返回 {code}"),
        Some(ureq::Error::Transport(t)) => match t.kind() {
            ureq::ErrorKind::Dns => "无法解析域名".into(),
            ureq::ErrorKind::ConnectionFailed => "无法连接".into(),
            ureq::ErrorKind::Io => "连接中断或超时".into(),
            _ => "网络错误".into(),
        },
        // Reading or parsing the response.
        None if e.is::<std::io::Error>() => "返回内容无法解析".into(),
        None => e.to_string(),
    }
}

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
fn musicbrainz(agent: &ureq::Agent, album: &Album, tocs: &[Toc]) -> Result<Vec<OnlineMatch>> {
    let s = &album.summary;
    let mut found = Vec::new();
    let mut error = None;
    let mut add = |r: Result<Vec<OnlineMatch>>, found: &mut Vec<OnlineMatch>| match r {
        Ok(v) => found.extend(v),
        Err(e) => error = Some(e),
    };
    for toc in tocs.iter().take(3) {
        add(musicbrainz::by_toc(agent, toc), &mut found);
    }
    if let Some(catalog) = &s.catalog {
        // "SVWC-70501~2": the first disc's number.
        let first = catalog.split(['~', '～']).next().unwrap_or(catalog).trim();
        add(musicbrainz::by_catalog(agent, first), &mut found);
    }
    if found.len() < 5 {
        add(
            musicbrainz::by_title(agent, &s.title, s.artist.as_deref()),
            &mut found,
        );
        if s.artist.is_some() && found.len() < 3 {
            add(musicbrainz::by_title(agent, &s.title, None), &mut found);
        }
    }
    match error {
        Some(e) if found.is_empty() => Err(e),
        _ => Ok(found),
    }
}

fn ctdb(agent: &ureq::Agent, tocs: &[Toc]) -> Result<Vec<OnlineMatch>> {
    let mut found = Vec::new();
    for toc in tocs.iter().take(3) {
        found.extend(ctdb::by_toc(agent, toc)?);
    }
    Ok(found)
}

/// Releases on the given `sources` that may be `album`, best matches first:
/// same disc, similar disc, same catalog number, then by title. The sources
/// are queried in parallel; one failing doesn't fail the others.
pub fn lookup(
    album: &Album,
    sources: &[OnlineSource],
    opts: &OnlineOptions,
) -> Result<OnlineResults> {
    let agent = &agent(opts)?;
    let tocs = tocs(album);
    let catalog = album.summary.catalog.as_deref().map(catalog_key);
    let results: Vec<(OnlineSource, Result<Vec<OnlineMatch>>)> = std::thread::scope(|scope| {
        let jobs: Vec<_> = sources
            .iter()
            .map(|&src| {
                let tocs = &tocs;
                let job = scope.spawn(move || match src {
                    OnlineSource::MusicBrainz => musicbrainz(agent, album, tocs),
                    OnlineSource::Bangumi => {
                        bangumi::search(agent, &album.summary.title, opts.prefer_chinese_title)
                    }
                    OnlineSource::Ctdb => ctdb(agent, tocs),
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
                errors.push(format!("{name}：{}", describe(&e)));
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
    Ok(OnlineResults { matches, errors })
}

/// Downloads a cover into `dir` as `<name>.jpg` (or `.png`), never
/// overwriting a file, and returns its path.
pub fn save_cover(url: &str, dir: &Path, name: &str, opts: &OnlineOptions) -> Result<PathBuf> {
    // Only a plain file name: no separators or other surprises.
    let name: String = name
        .chars()
        .filter(|c| c.is_alphanumeric() || matches!(c, '_' | '-' | ' '))
        .collect();
    let name = Some(name.trim())
        .filter(|n| !n.is_empty())
        .unwrap_or("cover");
    download_cover(&agent(opts)?, url, dir, name)
        .map_err(|e| anyhow!("封面下载失败：{}", describe(&e)))
}

fn download_cover(agent: &ureq::Agent, url: &str, dir: &Path, name: &str) -> Result<PathBuf> {
    let res = agent.get(url).call()?;
    let ext = match res.content_type() {
        "image/png" => "png",
        "image/jpeg" => "jpg",
        other => bail!("下载的不是图片（{other}）"),
    };
    let mut bytes = Vec::new();
    res.into_reader().take(64 << 20).read_to_end(&mut bytes)?;
    let path = (1..)
        .map(|n| match n {
            1 => dir.join(format!("{name}.{ext}")),
            n => dir.join(format!("{name} ({n}).{ext}")),
        })
        .find(|p| !p.exists())
        .unwrap();
    std::fs::write(&path, bytes)?;
    Ok(path)
}
