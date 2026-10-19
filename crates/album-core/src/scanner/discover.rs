//! Finding album folders inside the library root and fingerprinting them.

use album_formats::audio::{ext_of, is_audio_ext};
use crate::rules::{self, Rules};
use crate::util::{fnv1a, unix_secs};
use regex::Regex;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

static YEAR_DIR: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^(19|20)\d{2}$").unwrap());
pub static DISC_LIKE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)^(disc|disk|cd|dvd|bd|sacd)\s*[-_ ]?\s*\d+|^(flac|wav|alac|mp3|aac|dsd|dsf|dff|hi-?res|24bit|16bit|\d{2,3}k(hz)?)\b").unwrap()
});

const DISC_IMAGE_EXTS: &[&str] = &["iso", "mds", "mdf", "m2ts"];

fn is_hidden(p: &Path) -> bool {
    p.file_name().and_then(|n| n.to_str()).map(|n| n.starts_with('.') || n.starts_with('$')).unwrap_or(true)
}

fn subtree_has_media(dir: &Path) -> bool {
    walkdir::WalkDir::new(dir).max_depth(4).into_iter().filter_map(|e| e.ok()).any(|e| {
        e.file_type().is_file() && {
            let ext = ext_of(e.path());
            is_audio_ext(&ext) || DISC_IMAGE_EXTS.contains(&ext.as_str())
        }
    })
}

/// Walks the library and returns album folders.
pub fn discover(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    visit(root, 0, &rules::current(), &mut out);
    out.sort();
    out
}

fn visit(dir: &Path, depth: usize, rules: &Rules, out: &mut Vec<PathBuf>) {
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    let mut subdirs = Vec::new();
    let mut direct_media = false;
    for e in rd.filter_map(|e| e.ok()) {
        let p = e.path();
        if is_hidden(&p) {
            continue;
        }
        let Ok(ft) = e.file_type() else { continue };
        if ft.is_dir() {
            if p.file_name().map(|n| n.eq_ignore_ascii_case("BDMV")).unwrap_or(false) {
                direct_media = true;
            }
            subdirs.push(p);
        } else {
            let ext = ext_of(&p);
            if is_audio_ext(&ext) || ext == "cue" || DISC_IMAGE_EXTS.contains(&ext.as_str()) {
                direct_media = true;
            }
        }
    }
    let name = dir.file_name().and_then(|n| n.to_str()).unwrap_or("");
    if depth > 0 && !YEAR_DIR.is_match(name) {
        if rules.is_album_name(name) || direct_media {
            out.push(dir.to_path_buf());
            return;
        }
        let media_subdirs: Vec<_> = subdirs.iter().filter(|d| subtree_has_media(d)).collect();
        if media_subdirs.is_empty() {
            return;
        }
        let all_disc_like = media_subdirs.iter().all(|d| {
            d.file_name().and_then(|n| n.to_str()).map(|n| DISC_LIKE.is_match(n)).unwrap_or(false)
        });
        if all_disc_like || depth >= 2 {
            out.push(dir.to_path_buf());
            return;
        }
    }
    subdirs.sort();
    for d in subdirs {
        visit(&d, depth + 1, rules, out);
    }
}

#[derive(Debug, Clone)]
pub struct FileRec {
    pub path: PathBuf,
    /// Relative to the album folder, with '/' separators.
    pub rel: String,
    pub size: u64,
    pub mtime: i64,
    pub ext: String,
}

/// Lists all files of an album and returns a content fingerprint.
pub fn list_files(dir: &Path) -> (u64, Vec<FileRec>) {
    let mut files = Vec::new();
    for e in walkdir::WalkDir::new(dir).into_iter().filter_map(|e| e.ok()) {
        if !e.file_type().is_file() {
            continue;
        }
        let path = e.path().to_path_buf();
        let rel = path.strip_prefix(dir).unwrap_or(&path).to_string_lossy().replace('\\', "/");
        let meta = e.metadata().ok();
        let size = meta.as_ref().map(|m| m.len()).unwrap_or(0);
        let mtime = meta.map(|m| unix_secs(m.modified())).unwrap_or(0);
        let ext = ext_of(&path);
        files.push(FileRec { path, rel, size, mtime, ext });
    }
    files.sort_by(|a, b| crate::util::natural_cmp(&a.rel, &b.rel));
    let mut buf = Vec::new();
    for f in &files {
        buf.extend_from_slice(f.rel.as_bytes());
        buf.extend_from_slice(&f.size.to_le_bytes());
        buf.extend_from_slice(&f.mtime.to_le_bytes());
    }
    (fnv1a(&buf), files)
}
