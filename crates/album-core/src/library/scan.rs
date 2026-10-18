//! Full (incremental) and single-album scans.

use super::{cache, dirs, STATE};
use album_model::Album;
use crate::scanner::analyze;
use crate::scanner::discover::{discover, list_files};
use anyhow::Result;
use rayon::prelude::*;
use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};

/// Scans the library; unchanged albums (same fingerprint) are reused unless `force`.
/// Returns the number of re-analysed albums.
pub fn scan(force: bool, progress: impl Fn(usize, usize, &str) + Sync) -> Result<usize> {
    let (root, data) = dirs()?;
    let previous: HashMap<String, Album> = {
        let st = STATE.read().unwrap();
        st.albums.iter().map(|a| (a.summary.id.clone(), a.clone())).collect()
    };
    let album_dirs = discover(&root);
    let total = album_dirs.len();
    progress(0, total, "");
    let done = AtomicUsize::new(0);
    let rescanned = AtomicUsize::new(0);
    let mut albums: Vec<Album> = album_dirs
        .par_iter()
        .map(|dir| {
            let id = dir.strip_prefix(&root).unwrap_or(dir).to_string_lossy().replace('\\', "/");
            let (fp, files) = list_files(dir);
            let reuse = previous.get(&id).filter(|old| {
                !force
                    && old.fingerprint == fp
                    && old.summary.cover_thumb.as_ref().map(|t| Path::new(t).exists()).unwrap_or(true)
            });
            let album = match reuse {
                Some(old) => old.clone(),
                None => {
                    rescanned.fetch_add(1, Ordering::Relaxed);
                    analyze::analyze_files(&root, dir, &data, fp, files)
                }
            };
            let n = done.fetch_add(1, Ordering::Relaxed) + 1;
            progress(n, total, &album.summary.folder_name);
            album
        })
        .collect();
    albums.sort_by(|a, b| a.summary.id.cmp(&b.summary.id));
    let mut st = STATE.write().unwrap();
    st.albums = albums;
    cache::save_cache(&st)?;
    Ok(rescanned.into_inner())
}

pub fn rescan_album(id: &str) -> Result<Album> {
    let (root, data) = dirs()?;
    let dir = root.join(id);
    let album = analyze::analyze(&root, &dir, &data);
    let mut st = STATE.write().unwrap();
    match st.albums.iter_mut().find(|a| a.summary.id == id) {
        Some(slot) => *slot = album.clone(),
        None => st.albums.push(album.clone()),
    }
    cache::save_cache(&st)?;
    Ok(album)
}
