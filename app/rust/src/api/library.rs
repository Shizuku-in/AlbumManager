//! Functions exposed to Dart (see flutter_rust_bridge codegen).

use crate::api::models::*;
use album_formats::text;
use album_core::{imaging, library};
use crate::frb_generated::StreamSink;
use anyhow::{anyhow, Result};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Instant;

fn summaries() -> Vec<AlbumSummary> {
    library::STATE.read().unwrap().albums.iter().map(|a| a.summary.clone()).collect()
}

/// Loads config + cached library. Call once at startup.
pub fn init_library(data_dir: String) -> Result<LibraryInfo> {
    library::init(Path::new(&data_dir))?;
    let root = library::STATE.read().unwrap().root.as_ref().map(|r| r.to_string_lossy().into_owned());
    Ok(LibraryInfo { root, albums: summaries() })
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
            let _ = sink.lock().unwrap().add(ScanEvent::Started { total: total as i32 });
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
    Ok(imaging::thumbnail(Path::new(&path), &data, max_size)?.to_string_lossy().into_owned())
}

/// Reads a text file (log / cue / txt) with encoding detection.
pub fn read_text_file(path: String) -> Result<String> {
    Ok(text::read_decoded(Path::new(&path))?.text)
}

/// Converts every non-UTF-8 cue sheet of an album to UTF-8 (with BOM).
/// The original is kept next to it as `*.cue.bak`.
pub fn fix_cue_encoding(id: String) -> Result<Album> {
    let album = library::get(&id).ok_or_else(|| anyhow!("album not found"))?;
    for cue in album.cues.iter().filter(|c| !c.is_utf8) {
        let path = PathBuf::from(&cue.path);
        let bytes = std::fs::read(&path)?;
        let decoded = text::decode(&bytes);
        let backup = PathBuf::from(format!("{}.bak", cue.path));
        if !backup.exists() {
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
