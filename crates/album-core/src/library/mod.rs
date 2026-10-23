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
use std::sync::{LazyLock, Mutex, MutexGuard, RwLock};

#[derive(Default)]
struct State {
    data_dir: Option<PathBuf>,
    root: Option<PathBuf>,
    albums: Vec<Album>,
    overrides: overrides::Overrides,
}

static STATE: LazyLock<RwLock<State>> = LazyLock::new(|| RwLock::new(State::default()));

// One writer owns the complete operation, including analysis and persistence.
// Reject rather than queue: queued album IDs could belong to a different root.
static MUTATION: Mutex<()> = Mutex::new(());

fn begin_mutation() -> Result<MutexGuard<'static, ()>> {
    MUTATION
        .try_lock()
        .map_err(|_| anyhow!("专辑库正在更新，请完成后重试"))
}

pub fn init(data_dir: &Path) -> Result<()> {
    let _operation = begin_mutation()?;
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
    let _operation = begin_mutation()?;
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
    let _operation = begin_mutation()?;
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
    let _operation = begin_mutation()?;
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

pub fn root() -> Option<String> {
    STATE
        .read()
        .unwrap()
        .root
        .as_ref()
        .map(|r| r.to_string_lossy().into_owned())
}

pub fn data_dir() -> Result<PathBuf> {
    STATE
        .read()
        .unwrap()
        .data_dir
        .clone()
        .ok_or_else(|| anyhow!("library not initialised"))
}

pub fn summaries() -> Vec<AlbumSummary> {
    STATE
        .read()
        .unwrap()
        .albums
        .iter()
        .map(|a| a.summary.clone())
        .collect()
}

pub fn search_tracks(query: &str, titles: bool, artists: bool) -> Vec<String> {
    let q = query.trim().to_lowercase();
    if q.is_empty() || !(titles || artists) {
        return Vec::new();
    }
    let hit = |s: &str| s.to_lowercase().contains(&q);
    STATE
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

/// Stores the user's edits for an album (empty = back to detection) and
/// re-analyses it so cleared values return to their detected state.
pub fn set_override(id: &str, ov: AlbumOverride) -> Result<Album> {
    let _operation = begin_mutation()?;
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
    scan::rescan_album_locked(id)
}

/// File edits share the same writer gate as scans and root changes.
pub fn edit_album_files<T>(id: &str, edit: impl FnOnce(&Album) -> Result<T>) -> Result<T> {
    let _operation = begin_mutation()?;
    let album = get(id).ok_or_else(|| anyhow!("album not found"))?;
    edit(&album)
}

pub fn fix_cue_encoding(id: &str, include_missing_bom: bool, keep_backup: bool) -> Result<Album> {
    use album_formats::text;
    let _operation = begin_mutation()?;
    let album = get(id).ok_or_else(|| anyhow!("album not found"))?;
    for cue in album
        .cues
        .iter()
        .filter(|c| !c.is_utf8 || (include_missing_bom && c.missing_bom))
    {
        let path = Path::new(&cue.path);
        let bytes = std::fs::read(path)?;
        let decoded = text::decode(&bytes);
        let backup = PathBuf::from(format!("{}.bak", cue.path));
        if keep_backup && !backup.exists() {
            std::fs::write(&backup, &bytes)?;
        }
        let mut out = vec![0xEF, 0xBB, 0xBF];
        out.extend_from_slice(decoded.text.as_bytes());
        std::fs::write(path, out)?;
    }
    scan::rescan_album_locked(id)
}

pub fn clear_thumbnail_cache() -> Result<()> {
    let _operation = begin_mutation()?;
    let (_, data) = dirs()?;
    let dir = data.join("thumbs");
    if dir.exists() {
        std::fs::remove_dir_all(dir)?;
    }
    Ok(())
}
