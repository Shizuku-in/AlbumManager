//! On-disk persistence: `config.json` (library root, rules) and `library.json` (scan cache).

use super::STATE;
use album_model::{Album, RipRules, ScanRules};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

const CACHE_VERSION: u32 = 11;

#[derive(Serialize, Deserialize, Default)]
pub struct Config {
    pub root: Option<String>,
    #[serde(default)]
    pub rules: Option<ScanRules>,
    #[serde(default)]
    pub rip_rules: Option<RipRules>,
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

/// Called while holding the writer gate, but without a state lock. Serialize
/// borrowed albums under a read lock, then release it before disk I/O.
pub fn save_cache() -> Result<()> {
    #[derive(Serialize)]
    struct CacheRef<'a> {
        version: u32,
        root: std::borrow::Cow<'a, str>,
        albums: &'a [Album],
    }
    let (path, bytes) = {
        let st = STATE.read().unwrap();
        let (Some(data), Some(root)) = (&st.data_dir, &st.root) else {
            return Ok(());
        };
        let cache = CacheRef {
            version: CACHE_VERSION,
            root: root.to_string_lossy(),
            albums: &st.albums,
        };
        (cache_path(data), serde_json::to_vec(&cache)?)
    };
    let tmp = path.with_extension("tmp");
    std::fs::write(&tmp, bytes)?;
    std::fs::rename(tmp, path)?;
    Ok(())
}
