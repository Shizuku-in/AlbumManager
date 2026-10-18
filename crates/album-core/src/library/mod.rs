//! In-memory library state. Persistence lives in `cache`, scanning in `scan`.

mod cache;
mod scan;
#[cfg(test)]
mod tests;

pub use scan::{rescan_album, scan};

use album_model::Album;
use anyhow::{anyhow, Result};
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, RwLock};

#[derive(Default)]
pub struct State {
    pub data_dir: Option<PathBuf>,
    pub root: Option<PathBuf>,
    pub albums: Vec<Album>,
}

pub static STATE: LazyLock<RwLock<State>> = LazyLock::new(|| RwLock::new(State::default()));

pub fn init(data_dir: &Path) -> Result<()> {
    std::fs::create_dir_all(data_dir)?;
    let root = cache::load_config(data_dir).root.map(PathBuf::from);
    let albums = match &root {
        Some(r) => cache::load_cache(data_dir, r).unwrap_or_default(),
        None => Vec::new(),
    };
    let mut st = STATE.write().unwrap();
    st.data_dir = Some(data_dir.to_path_buf());
    st.root = root;
    st.albums = albums;
    Ok(())
}

pub fn set_root(root: &Path) -> Result<()> {
    if !root.is_dir() {
        return Err(anyhow!("目录不存在：{}", root.display()));
    }
    let mut st = STATE.write().unwrap();
    let data = st.data_dir.clone().ok_or_else(|| anyhow!("library not initialised"))?;
    if st.root.as_deref() != Some(root) {
        st.albums.clear();
    }
    st.root = Some(root.to_path_buf());
    cache::save_config(&data, &cache::Config { root: Some(root.to_string_lossy().into_owned()) })
}

/// (library root, app data dir)
pub fn dirs() -> Result<(PathBuf, PathBuf)> {
    let st = STATE.read().unwrap();
    let root = st.root.clone().ok_or_else(|| anyhow!("尚未设置专辑库目录"))?;
    let data = st.data_dir.clone().ok_or_else(|| anyhow!("library not initialised"))?;
    Ok((root, data))
}

pub fn get(id: &str) -> Option<Album> {
    STATE.read().unwrap().albums.iter().find(|a| a.summary.id == id).cloned()
}
