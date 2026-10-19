//! Thumbnail cache + dominant colour extraction.

use crate::util::fnv1a;
use anyhow::{Context, Result};
use image::codecs::jpeg::JpegEncoder;
use image::{DynamicImage, ImageReader};
use std::io::Cursor;
use std::path::{Path, PathBuf};

pub const IMAGE_EXTS: &[&str] = &["jpg", "jpeg", "png", "bmp", "tif", "tiff", "webp", "gif"];

pub fn is_image_ext(ext: &str) -> bool {
    IMAGE_EXTS.contains(&ext)
}

fn thumb_path(cache_dir: &Path, key: &str, max: u32) -> PathBuf {
    cache_dir
        .join("thumbs")
        .join(format!("{:016x}_{max}.jpg", fnv1a(key.as_bytes())))
}

fn source_key(src: &Path) -> String {
    let meta = std::fs::metadata(src).ok();
    let len = meta.as_ref().map(|m| m.len()).unwrap_or(0);
    let mtime = meta
        .and_then(|m| m.modified().ok())
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("{}|{len}|{mtime}", src.display())
}

fn save_jpeg(img: &DynamicImage, out: &Path) -> Result<()> {
    if let Some(dir) = out.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let rgb = img.to_rgb8();
    let tmp = out.with_extension("tmp");
    {
        let mut f = std::io::BufWriter::new(std::fs::File::create(&tmp)?);
        JpegEncoder::new_with_quality(&mut f, 88).encode_image(&rgb)?;
    }
    std::fs::rename(&tmp, out)?;
    Ok(())
}

fn decode_file(src: &Path) -> Result<DynamicImage> {
    let mut reader = ImageReader::open(src)?.with_guessed_format()?;
    reader.no_limits();
    reader
        .decode()
        .with_context(|| format!("decode {}", src.display()))
}

/// Returns a cached JPEG thumbnail (longest side <= max) for an image file.
pub fn thumbnail(src: &Path, cache_dir: &Path, max: u32) -> Result<PathBuf> {
    let out = thumb_path(cache_dir, &source_key(src), max);
    if out.exists() {
        return Ok(out);
    }
    // Scans can be several hundred MB (BMP/TIFF); decode those one at a time.
    let big = std::fs::metadata(src)
        .map(|m| m.len() > 48 * 1024 * 1024)
        .unwrap_or(false);
    let _guard = if big {
        Some(BIG_IMAGE_LOCK.lock().unwrap_or_else(|e| e.into_inner()))
    } else {
        None
    };
    if out.exists() {
        return Ok(out);
    }
    let img = decode_file(src)?;
    let small = if img.width() > max || img.height() > max {
        img.thumbnail(max, max)
    } else {
        img
    };
    drop(_guard);
    save_jpeg(&small, &out)?;
    Ok(out)
}

static BIG_IMAGE_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// Thumbnail from in-memory bytes (embedded cover art), keyed by the audio file.
pub fn thumbnail_from_bytes(
    bytes: &[u8],
    key_src: &Path,
    cache_dir: &Path,
    max: u32,
) -> Result<PathBuf> {
    let out = thumb_path(cache_dir, &format!("embedded|{}", source_key(key_src)), max);
    if out.exists() {
        return Ok(out);
    }
    let img = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()?
        .decode()?;
    let small = if img.width() > max || img.height() > max {
        img.thumbnail(max, max)
    } else {
        img
    };
    save_jpeg(&small, &out)?;
    Ok(out)
}

/// Picks a pleasant dominant colour: the most "present" saturated hue bucket.
pub fn accent_color(thumb: &Path) -> Option<u32> {
    let img = image::open(thumb).ok()?.thumbnail(48, 48).to_rgb8();
    const BUCKETS: usize = 12;
    let mut weight = [0f64; BUCKETS];
    let mut sum = [[0f64; 3]; BUCKETS];
    let (mut gr, mut gg, mut gb, mut n) = (0f64, 0f64, 0f64, 0f64);
    for p in img.pixels() {
        let [r, g, b] = p.0.map(|c| c as f64 / 255.0);
        let max = r.max(g).max(b);
        let min = r.min(g).min(b);
        let l = (max + min) / 2.0;
        let d = max - min;
        gr += r;
        gg += g;
        gb += b;
        n += 1.0;
        if d < 0.08 || !(0.12..=0.92).contains(&l) {
            continue;
        }
        let s = d / (1.0 - (2.0 * l - 1.0).abs()).max(1e-6);
        let h = if max == r {
            ((g - b) / d).rem_euclid(6.0)
        } else if max == g {
            (b - r) / d + 2.0
        } else {
            (r - g) / d + 4.0
        } / 6.0;
        let i = ((h * BUCKETS as f64) as usize).min(BUCKETS - 1);
        let w = s * (1.0 - (l - 0.5).abs());
        weight[i] += w;
        sum[i][0] += r * w;
        sum[i][1] += g * w;
        sum[i][2] += b * w;
    }
    let (best, &bw) = weight
        .iter()
        .enumerate()
        .max_by(|a, b| a.1.total_cmp(b.1))?;
    let (r, g, b) = if bw > n * 0.03 {
        (sum[best][0] / bw, sum[best][1] / bw, sum[best][2] / bw)
    } else {
        // Mostly greyscale cover: use the average colour.
        (gr / n, gg / n, gb / n)
    };
    let to = |v: f64| (v.clamp(0.0, 1.0) * 255.0).round() as u32;
    Some(0xFF00_0000 | (to(r) << 16) | (to(g) << 8) | to(b))
}
