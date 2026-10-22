//! Functions exposed to Dart (see flutter_rust_bridge codegen).

use crate::api::models::*;
use crate::frb_generated::StreamSink;
use album_core::{imaging, library, rules};
use album_formats::{riplog, text};
use anyhow::{anyhow, Result};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Instant;

fn summaries() -> Vec<AlbumSummary> {
    library::STATE
        .read()
        .unwrap()
        .albums
        .iter()
        .map(|a| a.summary.clone())
        .collect()
}

/// Loads config + cached library. Call once at startup.
pub fn init_library(data_dir: String) -> Result<LibraryInfo> {
    library::init(Path::new(&data_dir))?;
    let root = library::STATE
        .read()
        .unwrap()
        .root
        .as_ref()
        .map(|r| r.to_string_lossy().into_owned());
    Ok(LibraryInfo {
        root,
        albums: summaries(),
    })
}

pub fn set_library_root(root: String) -> Result<()> {
    library::set_root(Path::new(&root))
}

/// Scans the library, streaming progress. Unchanged albums come from the cache unless `force`.
pub fn scan_library(force: bool, sink: StreamSink<ScanEvent>) -> Result<()> {
    let start = Instant::now();
    let sink = Mutex::new(sink);
    let last = Mutex::new(Instant::now());
    let rescanned = library::scan(force, |done, total, current| {
        // Throttle UI updates to ~30/s.
        let mut l = last.lock().unwrap();
        if done == 0 {
            let _ = sink.lock().unwrap().add(ScanEvent::Started {
                total: total as i32,
            });
        } else if done == total || l.elapsed().as_millis() >= 33 {
            *l = Instant::now();
            let _ = sink.lock().unwrap().add(ScanEvent::Progress {
                done: done as i32,
                total: total as i32,
                current: current.to_string(),
            });
        }
    })?;
    let _ = sink.lock().unwrap().add(ScanEvent::Finished {
        albums: summaries(),
        elapsed_ms: start.elapsed().as_millis() as i64,
        rescanned: rescanned as i32,
    });
    Ok(())
}

/// Ids of the albums with a track whose title (`titles`) or artist (`artists`)
/// contains `query`, ignoring case. Sync: it only walks the in-memory library.
#[flutter_rust_bridge::frb(sync)]
pub fn search_tracks(query: String, titles: bool, artists: bool) -> Vec<String> {
    let q = query.trim().to_lowercase();
    if q.is_empty() || !(titles || artists) {
        return Vec::new();
    }
    let hit = |s: &str| s.to_lowercase().contains(&q);
    library::STATE
        .read()
        .unwrap()
        .albums
        .iter()
        .filter(|a| {
            a.discs.iter().flat_map(|d| &d.tracks).any(|t| {
                (titles && hit(&t.title)) || (artists && t.artist.as_deref().is_some_and(hit))
            })
        })
        .map(|a| a.summary.id.clone())
        .collect()
}

/// Releases on the given online databases that may be this album, best
/// matches first.
pub fn lookup_online(id: String, sources: Vec<OnlineSource>) -> Result<OnlineResults> {
    let album = library::get(&id).ok_or_else(|| anyhow!("album not found"))?;
    Ok(album_online::lookup(&album, &sources))
}

/// Downloads a cover found online into the album folder (never overwriting a
/// file) and returns its path.
pub fn save_online_cover(id: String, url: String) -> Result<String> {
    let album = library::get(&id).ok_or_else(|| anyhow!("album not found"))?;
    let path = album_online::save_cover(&url, Path::new(&album.summary.path))?;
    Ok(path.to_string_lossy().into_owned())
}

pub fn get_album(id: String) -> Option<Album> {
    library::get(&id)
}

pub fn rescan_album(id: String) -> Result<Album> {
    library::rescan_album(&id)
}

/// Saves the user's edits for an album (all `None` = back to detection) and
/// returns the re-analysed album.
pub fn set_album_override(id: String, overrides: AlbumOverride) -> Result<Album> {
    library::set_override(&id, overrides)
}

/// Cached JPEG thumbnail path for any image (scans can be huge BMP/TIFF).
pub fn get_thumbnail(path: String, max_size: u32) -> Result<String> {
    let (_, data) = library::dirs()?;
    Ok(imaging::thumbnail(Path::new(&path), &data, max_size)?
        .to_string_lossy()
        .into_owned())
}

/// Reads a text file (log / cue / txt) with encoding detection.
pub fn read_text_file(path: String) -> Result<String> {
    let path = Path::new(&path);
    let is_log = path
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("log"));
    Ok(if is_log {
        riplog::read(path)?
    } else {
        text::read_decoded(path)?
    }
    .text)
}

/// An EAC log written in another UI language, translated to English; None
/// when it is English already or the language isn't known.
pub fn translate_log(path: String) -> Result<Option<String>> {
    let text = riplog::read(Path::new(&path))?.text;
    Ok(riplog::translate(&text).map(|(_, english)| english))
}

/// Rewrites an album's non-UTF-8 cue sheets as UTF-8 with BOM, and with
/// `include_missing_bom` also UTF-8 ones that lack the BOM. With
/// `keep_backup` the original is kept next to it as `*.cue.bak`.
pub fn fix_cue_encoding(id: String, include_missing_bom: bool, keep_backup: bool) -> Result<Album> {
    let album = library::get(&id).ok_or_else(|| anyhow!("album not found"))?;
    for cue in album
        .cues
        .iter()
        .filter(|c| !c.is_utf8 || (include_missing_bom && c.missing_bom))
    {
        let path = PathBuf::from(&cue.path);
        let bytes = std::fs::read(&path)?;
        let decoded = text::decode(&bytes);
        let backup = PathBuf::from(format!("{}.bak", cue.path));
        if keep_backup && !backup.exists() {
            std::fs::write(&backup, &bytes)?;
        }
        let mut out = vec![0xEF, 0xBB, 0xBF];
        out.extend_from_slice(decoded.text.as_bytes());
        std::fs::write(&path, out)?;
    }
    library::rescan_album(&id)
}

/// Removes all cached thumbnails (they are regenerated on next scan).
pub fn clear_thumbnail_cache() -> Result<()> {
    let (_, data) = library::dirs()?;
    let dir = data.join("thumbs");
    if dir.exists() {
        std::fs::remove_dir_all(dir)?;
    }
    Ok(())
}

/// Where the app keeps its data and how much the thumbnail cache takes.
pub fn cache_info() -> Result<CacheInfo> {
    let data = library::STATE
        .read()
        .unwrap()
        .data_dir
        .clone()
        .ok_or_else(|| anyhow!("library not initialised"))?;
    let (mut count, mut bytes) = (0, 0);
    if let Ok(entries) = std::fs::read_dir(data.join("thumbs")) {
        for m in entries
            .flatten()
            .filter_map(|e| e.metadata().ok())
            .filter(|m| m.is_file())
        {
            count += 1;
            bytes += m.len() as i64;
        }
    }
    Ok(CacheInfo {
        data_dir: data.to_string_lossy().into_owned(),
        thumb_count: count,
        thumb_bytes: bytes,
    })
}

pub fn get_scan_rules() -> ScanRules {
    rules::current().source.clone()
}

pub fn default_scan_rules() -> ScanRules {
    rules::defaults()
}

pub fn get_rip_rules() -> RipRules {
    rules::rip()
}

pub fn default_rip_rules() -> RipRules {
    riplog::default_rules()
}

/// The log checker rules the user can count as problems or not.
pub fn rip_deduction_kinds() -> Vec<DeductionKind> {
    riplog::deduction_kinds()
}

/// Applies new rip log rules to the whole library right away; returns the
/// updated album summaries.
pub fn set_rip_rules(rules: RipRules) -> Result<Vec<AlbumSummary>> {
    library::set_rip_rules(rules)
}

/// Fails with a readable message when a template is invalid.
pub fn set_scan_rules(rules: ScanRules) -> Result<()> {
    library::set_rules(rules)
}
