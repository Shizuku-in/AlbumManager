//! Audio file probing: stream properties + basic tags.

use lofty::config::ParseOptions;
use lofty::prelude::*;
use lofty::probe::Probe;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

pub const AUDIO_EXTS: &[&str] = &[
    "flac", "wav", "ape", "tak", "tta", "wv", "dsf", "dff", "mp3", "m4a", "aac", "ogg", "opus", "aiff", "aif", "alac",
];
pub const LOSSY_EXTS: &[&str] = &["mp3", "m4a", "aac", "ogg", "opus"];

pub fn is_audio_ext(ext: &str) -> bool {
    AUDIO_EXTS.contains(&ext)
}

#[derive(Debug, Default, Clone)]
pub struct AudioInfo {
    pub format: String,
    pub duration: f64,
    pub sample_rate: u32,
    pub bit_depth: u32,
    pub channels: u32,
    pub bitrate_kbps: u32,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub genre: Option<String>,
    pub track: Option<u32>,
    pub disc: Option<u32>,
    pub date: Option<String>,
    pub is_dsd: bool,
}

pub fn ext_of(path: &Path) -> String {
    path.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase()
}

pub fn probe(path: &Path) -> AudioInfo {
    let ext = ext_of(path);
    let mut info = AudioInfo { format: ext.to_ascii_uppercase(), ..Default::default() };
    match ext.as_str() {
        "dsf" => {
            if let Some((rate, dur, ch)) = probe_dsf(path) {
                info.sample_rate = rate;
                info.duration = dur;
                info.channels = ch;
                info.bit_depth = 1;
                info.is_dsd = true;
            }
            // DSF keeps ID3v2 at the end — lofty can read it via the generic probe.
            read_tags_only(path, &mut info);
            return info;
        }
        "dff" => {
            info.is_dsd = true;
            info.bit_depth = 1;
            return info;
        }
        "tta" => {
            if let Some((rate, bits, ch, dur)) = probe_tta(path) {
                info.sample_rate = rate;
                info.bit_depth = bits;
                info.channels = ch;
                info.duration = dur;
            }
            return info;
        }
        "tak" => {
            if let Some((rate, bits, ch, dur)) = probe_tak(path) {
                info.sample_rate = rate;
                info.bit_depth = bits;
                info.channels = ch;
                info.duration = dur;
            }
            return info;
        }
        _ => {}
    }
    let opts = ParseOptions::new().read_cover_art(false);
    let Ok(probe) = Probe::open(path).map(|p| p.options(opts)) else { return info };
    let Ok(tagged) = probe.read() else { return info };
    let props = tagged.properties();
    info.duration = props.duration().as_secs_f64();
    info.sample_rate = props.sample_rate().unwrap_or(0);
    info.bit_depth = props.bit_depth().unwrap_or(0) as u32;
    info.channels = props.channels().unwrap_or(0) as u32;
    info.bitrate_kbps = props.audio_bitrate().unwrap_or(0);
    if let Some(tag) = tagged.primary_tag().or_else(|| tagged.first_tag()) {
        fill_tags(tag, &mut info);
    }
    info
}

fn read_tags_only(path: &Path, info: &mut AudioInfo) {
    let opts = ParseOptions::new().read_cover_art(false).read_properties(false);
    let tagged = Probe::open(path)
        .ok()
        .and_then(|p| p.options(opts).guess_file_type().ok())
        .and_then(|p| p.read().ok());
    if let Some(tagged) = tagged {
        if let Some(tag) = tagged.primary_tag().or_else(|| tagged.first_tag()) {
            fill_tags(tag, info);
        }
    }
}

fn clean(s: Option<std::borrow::Cow<'_, str>>) -> Option<String> {
    s.map(|v| v.trim().to_string()).filter(|v| !v.is_empty())
}

fn fill_tags(tag: &lofty::tag::Tag, info: &mut AudioInfo) {
    info.title = clean(tag.title());
    info.artist = clean(tag.artist());
    info.album = clean(tag.album());
    info.genre = clean(tag.genre());
    info.track = tag.track();
    info.disc = tag.disk();
    info.album_artist = tag.get_string(&ItemKey::AlbumArtist).map(|s| s.trim().to_string()).filter(|s| !s.is_empty());
    info.date = tag
        .get_string(&ItemKey::RecordingDate)
        .or_else(|| tag.get_string(&ItemKey::Year))
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
}

/// Returns (sample rate, duration secs, channels).
fn probe_dsf(path: &Path) -> Option<(u32, f64, u32)> {
    let mut f = File::open(path).ok()?;
    let mut hdr = [0u8; 28 + 52];
    f.read_exact(&mut hdr).ok()?;
    if &hdr[0..4] != b"DSD " || &hdr[28..32] != b"fmt " {
        return None;
    }
    let fmt = &hdr[28..];
    let channels = u32::from_le_bytes(fmt[24..28].try_into().ok()?);
    let rate = u32::from_le_bytes(fmt[28..32].try_into().ok()?);
    let samples = u64::from_le_bytes(fmt[36..44].try_into().ok()?);
    if rate == 0 {
        return None;
    }
    Some((rate, samples as f64 / rate as f64, channels))
}

/// Returns (sample rate, bits, channels, duration secs).
fn probe_tta(path: &Path) -> Option<(u32, u32, u32, f64)> {
    let mut f = File::open(path).ok()?;
    let mut buf = [0u8; 10];
    f.read_exact(&mut buf).ok()?;
    // Optional leading ID3v2 tag.
    if &buf[0..3] == b"ID3" {
        let size = ((buf[6] as u64 & 0x7f) << 21) | ((buf[7] as u64 & 0x7f) << 14) | ((buf[8] as u64 & 0x7f) << 7) | (buf[9] as u64 & 0x7f);
        f.seek(SeekFrom::Start(10 + size)).ok()?;
    } else {
        f.seek(SeekFrom::Start(0)).ok()?;
    }
    let mut h = [0u8; 18];
    f.read_exact(&mut h).ok()?;
    if &h[0..4] != b"TTA1" {
        return None;
    }
    let channels = u16::from_le_bytes([h[6], h[7]]) as u32;
    let bits = u16::from_le_bytes([h[8], h[9]]) as u32;
    let rate = u32::from_le_bytes(h[10..14].try_into().ok()?);
    let len = u32::from_le_bytes(h[14..18].try_into().ok()?);
    if rate == 0 {
        return None;
    }
    Some((rate, bits, channels, len as f64 / rate as f64))
}

/// TAK STREAMINFO (layout as in FFmpeg's tak.c, little-endian bit order).
/// Returns (sample rate, bits, channels, duration secs).
fn probe_tak(path: &Path) -> Option<(u32, u32, u32, f64)> {
    let mut f = File::open(path).ok()?;
    let mut magic = [0u8; 4];
    f.read_exact(&mut magic).ok()?;
    if &magic != b"tBaK" {
        return None;
    }
    loop {
        let mut hdr = [0u8; 4];
        f.read_exact(&mut hdr).ok()?;
        let kind = hdr[0] & 0x7f;
        let size = u32::from_le_bytes([hdr[1], hdr[2], hdr[3], 0]) as usize;
        if kind == 0 {
            return None; // end of metadata
        }
        if kind != 1 {
            f.seek(SeekFrom::Current(size as i64)).ok()?;
            continue;
        }
        let mut buf = vec![0u8; size.min(64)];
        f.read_exact(&mut buf).ok()?;
        let mut pos = 0usize;
        let mut bits = |n: usize| -> u64 {
            let mut v = 0u64;
            for i in 0..n {
                let byte = buf.get((pos + i) / 8).copied().unwrap_or(0);
                v |= (((byte >> ((pos + i) % 8)) & 1) as u64) << i;
            }
            pos += n;
            v
        };
        let _codec = bits(6);
        let _profile = bits(4);
        let _frame_size = bits(4);
        let samples = bits(35);
        let _data_type = bits(3);
        let rate = bits(18) as u32 + 6000;
        let bps = bits(5) as u32 + 8;
        let channels = bits(4) as u32 + 1;
        return Some((rate, bps, channels, samples as f64 / rate as f64));
    }
}

/// Embedded front cover of an audio file, if any.
pub fn embedded_cover(path: &Path) -> Option<Vec<u8>> {
    let tagged = Probe::open(path).ok()?.guess_file_type().ok()?.read().ok()?;
    for tag in tagged.tags() {
        let pics = tag.pictures();
        let pic = pics
            .iter()
            .find(|p| p.pic_type() == lofty::picture::PictureType::CoverFront)
            .or_else(|| pics.first());
        if let Some(p) = pic {
            return Some(p.data().to_vec());
        }
    }
    None
}
