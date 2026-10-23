//! In-memory library state. Persistence lives in `cache`, scanning in `scan`.

mod cache;
mod overrides;
mod scan;
#[cfg(test)]
mod tests;

pub use scan::{rescan_album, scan};

use crate::rules;
use crate::scanner::analyze;
use album_model::{Album, AlbumOverride, AlbumSummary, RipRules, ScanRules};
use anyhow::{anyhow, Result};
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, RwLock};

#[derive(Default)]
pub struct State {
    pub data_dir: Option<PathBuf>,
    pub root: Option<PathBuf>,
    pub albums: Vec<Album>,
    pub overrides: overrides::Overrides,
}

pub static STATE: LazyLock<RwLock<State>> = LazyLock::new(|| RwLock::new(State::default()));

pub fn init(data_dir: &Path) -> Result<()> {
    std::fs::create_dir_all(data_dir)?;
    let cfg = cache::load_config(data_dir);
    // Invalid saved rules fall back to the defaults rather than failing startup.
    if rules::set(cfg.rules.unwrap_or_else(rules::defaults)).is_err() {
        rules::set(rules::defaults())?;
    }
    rules::set_rip(
        cfg.rip_rules
            .unwrap_or_else(album_formats::riplog::default_rules),
    );
    let root = cfg.root.map(PathBuf::from);
    overrides::migrate(data_dir, root.as_deref())?;
    let edits = root
        .as_deref()
        .map(|r| overrides::load(data_dir, r))
        .transpose()?
        .unwrap_or_default();
    let albums = match &root {
        Some(r) => cache::load_cache(data_dir, r).unwrap_or_default(),
        None => Vec::new(),
    };
    let mut st = STATE.write().unwrap();
    st.data_dir = Some(data_dir.to_path_buf());
    st.root = root;
    st.albums = albums;
    st.overrides = edits;
    Ok(())
}

pub fn set_root(root: &Path) -> Result<()> {
    if !root.is_dir() {
        return Err(anyhow!("目录不存在：{}", root.display()));
    }
    let mut st = STATE.write().unwrap();
    let data = st
        .data_dir
        .clone()
        .ok_or_else(|| anyhow!("library not initialised"))?;
    let edits = overrides::load(&data, root)?;
    let mut cfg = cache::load_config(&data);
    cfg.root = Some(root.to_string_lossy().into_owned());
    cache::save_config(&data, &cfg)?;
    if st.root.as_deref() != Some(root) {
        st.albums.clear();
    }
    st.root = Some(root.to_path_buf());
    st.overrides = edits;
    Ok(())
}

/// Validates, installs and saves recognition rules. Takes effect on the next
/// full scan.
pub fn set_rules(r: ScanRules) -> Result<()> {
    rules::set(r.clone())?;
    let data = STATE
        .read()
        .unwrap()
        .data_dir
        .clone()
        .ok_or_else(|| anyhow!("library not initialised"))?;
    let mut cfg = cache::load_config(&data);
    cfg.rules = Some(r);
    cache::save_config(&data, &cfg)
}

/// Installs new rip log rules and re-judges every album's logs with them
/// (no files are read). Returns the updated summaries.
pub fn set_rip_rules(r: RipRules) -> Result<Vec<AlbumSummary>> {
    rules::set_rip(r.clone());
    let mut st = STATE.write().unwrap();
    let data = st
        .data_dir
        .clone()
        .ok_or_else(|| anyhow!("library not initialised"))?;
    let mut cfg = cache::load_config(&data);
    cfg.rip_rules = Some(r);
    cache::save_config(&data, &cfg)?;
    for album in st.albums.iter_mut() {
        let source = album.summary.source;
        analyze::apply_source(&mut album.summary, &mut album.logs, source);
    }
    cache::save_cache(&st)?;
    Ok(st.albums.iter().map(|a| a.summary.clone()).collect())
}

/// (library root, app data dir)
pub fn dirs() -> Result<(PathBuf, PathBuf)> {
    let st = STATE.read().unwrap();
    let root = st
        .root
        .clone()
        .ok_or_else(|| anyhow!("尚未设置专辑库目录"))?;
    let data = st
        .data_dir
        .clone()
        .ok_or_else(|| anyhow!("library not initialised"))?;
    Ok((root, data))
}

pub fn get(id: &str) -> Option<Album> {
    STATE
        .read()
        .unwrap()
        .albums
        .iter()
        .find(|a| a.summary.id == id)
        .cloned()
}

/// Stores the user's edits for an album (empty = back to detection) and
/// re-analyses it so cleared values return to their detected state.
pub fn set_override(id: &str, ov: AlbumOverride) -> Result<Album> {
    {
        let mut st = STATE.write().unwrap();
        let data = st
            .data_dir
            .clone()
            .ok_or_else(|| anyhow!("library not initialised"))?;
        if ov == AlbumOverride::default() {
            st.overrides.remove(id);
        } else {
            st.overrides.insert(id.to_string(), ov);
        }
        let root = st
            .root
            .as_ref()
            .ok_or_else(|| anyhow!("尚未设置专辑库目录"))?;
        overrides::save(&data, root, &st.overrides)?;
    }
    rescan_album(id)
}
