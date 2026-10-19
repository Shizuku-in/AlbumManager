//! On-disk persistence: `config.json` (library root, rules) and `library.json` (scan cache).

use super::State;
use album_model::{Album, ScanRules};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

const CACHE_VERSION: u32 = 2;

#[derive(Serialize, Deserialize, Default)]
pub struct Config {
    pub root: Option<String>,
    #[serde(default)]
    pub rules: Option<ScanRules>,
}

#[derive(Serialize, Deserialize)]
struct Cache {
    version: u32,
    root: String,
    albums: Vec<Album>,
}

fn config_path(data: &Path) -> PathBuf {
    data.join("config.json")
}
fn cache_path(data: &Path) -> PathBuf {
    data.join("library.json")
}

pub fn load_config(data: &Path) -> Config {
    std::fs::read(config_path(data))
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_default()
}

pub fn save_config(data: &Path, cfg: &Config) -> Result<()> {
    std::fs::write(config_path(data), serde_json::to_vec_pretty(cfg)?)?;
    Ok(())
}

pub fn load_cache(data: &Path, root: &Path) -> Option<Vec<Album>> {
    let bytes = std::fs::read(cache_path(data)).ok()?;
    let cache: Cache = serde_json::from_slice(&bytes).ok()?;
    (cache.version == CACHE_VERSION && Path::new(&cache.root) == root).then_some(cache.albums)
}

pub fn save_cache(st: &State) -> Result<()> {
    let (Some(data), Some(root)) = (&st.data_dir, &st.root) else { return Ok(()) };
    let cache = Cache { version: CACHE_VERSION, root: root.to_string_lossy().into_owned(), albums: st.albums.clone() };
    let tmp = cache_path(data).with_extension("tmp");
    std::fs::write(&tmp, serde_json::to_vec(&cache)?)?;
    std::fs::rename(tmp, cache_path(data))?;
    Ok(())
}
