//! Hand-edited album values (`overrides.json`), re-applied on top of every
//! analysis so rescans keep them.

use crate::rules;
use crate::scanner::analyze;
use album_model::{Album, AlbumOverride};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

pub type Overrides = HashMap<String, AlbumOverride>;

fn path(data: &Path) -> PathBuf {
    data.join("overrides.json")
}

#[derive(Default, Serialize, Deserialize)]
struct Store {
    libraries: HashMap<String, Overrides>,
}

fn library_key(root: &Path) -> String {
    let key = root.to_string_lossy().replace('\\', "/");
    let key = key.trim_end_matches('/');
    if cfg!(windows) {
        key.to_lowercase()
    } else {
        key.to_string()
    }
}

fn read(data: &Path) -> Result<Option<Vec<u8>>> {
    match std::fs::read(path(data)) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.into()),
    }
}

/// Old unscoped edits belong only to the library saved before upgrading.
pub fn migrate(data: &Path, root: Option<&Path>) -> Result<()> {
    let Some(bytes) = read(data)? else {
        return Ok(());
    };
    if serde_json::from_slice::<Store>(&bytes).is_ok() {
        return Ok(());
    }
    let edits: Overrides = serde_json::from_slice(&bytes)?;
    let mut store = Store::default();
    if let Some(root) = root {
        store.libraries.insert(library_key(root), edits);
    } else if !edits.is_empty() {
        anyhow::bail!("旧版编辑数据缺少所属专辑库，无法迁移");
    }
    write(data, &store)
}

fn load_store(data: &Path) -> Result<Store> {
    match read(data)? {
        Some(bytes) => Ok(serde_json::from_slice(&bytes)?),
        None => Ok(Store::default()),
    }
}

pub fn load(data: &Path, root: &Path) -> Result<Overrides> {
    Ok(load_store(data)?
        .libraries
        .remove(&library_key(root))
        .unwrap_or_default())
}

pub fn save(data: &Path, root: &Path, overrides: &Overrides) -> Result<()> {
    let mut store = load_store(data)?;
    store.libraries.insert(library_key(root), overrides.clone());
    write(data, &store)
}

fn write(data: &Path, store: &Store) -> Result<()> {
    let tmp = path(data).with_extension("tmp");
    std::fs::write(&tmp, serde_json::to_vec_pretty(store)?)?;
    std::fs::rename(tmp, path(data))?;
    Ok(())
}

/// Applies `ov` to a freshly analysed album.
pub fn apply(album: &mut Album, ov: &AlbumOverride, cache_dir: &Path) {
    if let Some(source) = ov.source {
        analyze::apply_source(&mut album.summary, &mut album.logs, source);
    }
    if let Some(cover) = &ov.cover_path {
        // A cover that was moved or deleted falls back to the detected one.
        analyze::apply_cover(&mut album.summary, Path::new(cover), cache_dir);
    }
    if let Some(v) = ov.has_scans {
        album.summary.has_scans = v;
    }
    if let Some(v) = &ov.title {
        album.summary.title = v.clone();
    }
    if let Some(v) = &ov.artist {
        album.summary.artist = Some(v.clone());
    }
    if let Some((date, year)) = ov.date.as_deref().and_then(rules::parse_typed_date) {
        album.summary.date = Some(date);
        album.summary.year = Some(year);
    }
    if let Some(v) = &ov.genre {
        album.summary.genre = Some(v.clone());
    }
    if let Some(v) = &ov.catalog {
        album.summary.catalog = Some(v.clone());
    }
    if let Some(v) = &ov.event {
        album.summary.event = Some(v.clone());
    }
    album.summary.overrides = ov.clone();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migrates_edits_once_and_keeps_libraries_separate() {
        let data = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target")
            .join(format!(
                "album-overrides-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            ));
        std::fs::create_dir(&data).unwrap();
        let a = Path::new("/music/a");
        let b = Path::new("/music/b");
        let edits = Overrides::from([(
            "same-album".into(),
            AlbumOverride {
                title: Some("旧库标题".into()),
                ..Default::default()
            },
        )]);
        std::fs::write(path(&data), serde_json::to_vec(&edits).unwrap()).unwrap();
        migrate(&data, Some(a)).unwrap();
        assert_eq!(load(&data, a).unwrap(), edits);
        assert!(load(&data, b).unwrap().is_empty());
        let other = Overrides::from([(
            "same-album".into(),
            AlbumOverride {
                title: Some("新库标题".into()),
                ..Default::default()
            },
        )]);
        save(&data, b, &other).unwrap();
        migrate(&data, Some(b)).unwrap();
        assert_eq!(load(&data, a).unwrap(), edits);
        assert_eq!(load(&data, b).unwrap(), other);
        std::fs::remove_dir_all(data).unwrap();
    }
}
