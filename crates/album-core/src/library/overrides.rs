//! Hand-edited album values (`overrides.json`), re-applied on top of every
//! analysis so rescans keep them.

use crate::scanner::analyze;
use album_model::{Album, AlbumOverride};
use anyhow::Result;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

pub type Overrides = HashMap<String, AlbumOverride>;

fn path(data: &Path) -> PathBuf {
    data.join("overrides.json")
}

pub fn load(data: &Path) -> Overrides {
    std::fs::read(path(data))
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_default()
}

pub fn save(data: &Path, overrides: &Overrides) -> Result<()> {
    let tmp = path(data).with_extension("tmp");
    std::fs::write(&tmp, serde_json::to_vec_pretty(overrides)?)?;
    std::fs::rename(tmp, path(data))?;
    Ok(())
}

/// Applies `ov` to a freshly analysed album.
pub fn apply(album: &mut Album, ov: &AlbumOverride, cache_dir: &Path) {
    if let Some(source) = ov.source {
        analyze::apply_source(&mut album.summary, &album.logs, source);
    }
    if let Some(cover) = &ov.cover_path {
        // A cover that was moved or deleted falls back to the detected one.
        analyze::apply_cover(&mut album.summary, Path::new(cover), cache_dir);
    }
    album.summary.overrides = ov.clone();
}
