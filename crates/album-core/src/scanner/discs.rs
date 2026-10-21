//! Builds the disc / track structure of an album from cue sheets and audio files.

use super::discover::{FileRec, DISC_LIKE};
use crate::util::{first_number, natural_cmp};
use album_formats::audio::{self, AudioInfo};
use album_formats::{cue, text};
use album_model::{CueInfo, Disc, Track};
use regex::Regex;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::LazyLock;

static DISC_IN_NAME: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)(disc|disk|cd)\s*[-_ ]?\s*(\d+)").unwrap());
static LEADING_NUM: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^(?:(\d{1,2})[-.])?(\d{1,3})(?:\s*[-._)]\s*|\s+)(.+)$").unwrap());

pub struct DiscBuild {
    pub discs: Vec<Disc>,
    pub cues: Vec<CueInfo>,
    pub cue_sheets: Vec<cue::CueSheet>,
}

fn disc_number_from(s: &str) -> Option<i32> {
    DISC_IN_NAME.captures(s).and_then(|c| c[2].parse().ok())
}

fn parent_rel(rel: &str) -> &str {
    rel.rsplit_once('/').map(|(d, _)| d).unwrap_or("")
}

fn stem(rel: &str) -> String {
    let name = rel.rsplit('/').next().unwrap_or(rel);
    name.rsplit_once('.')
        .map(|(s, _)| s)
        .unwrap_or(name)
        .to_string()
}

fn file_name(rel: &str) -> &str {
    rel.rsplit('/').next().unwrap_or(rel)
}

/// Lowercased name without extension, ignoring whitespace and characters that are
/// forbidden in Windows file names (ASCII or their full-width replacements).
fn loose_stem(name: &str) -> String {
    let base = match name.rsplit_once('.') {
        Some((s, ext)) if !ext.is_empty() && ext.len() <= 5 && !ext.contains(' ') => s,
        _ => name,
    };
    use unicode_normalization::UnicodeNormalization;
    base.nfc()
        .filter(|c| !c.is_whitespace() && !"/\\:*?\"<>|／＼：＊？＂＜＞｜".contains(*c))
        .flat_map(|c| c.to_lowercase())
        .collect()
}

fn make_track(
    number: i32,
    title: String,
    artist: Option<String>,
    dur: f64,
    start: Option<f64>,
    f: &FileRec,
    a: &AudioInfo,
) -> Track {
    Track {
        number,
        title,
        artist,
        duration_secs: dur.max(0.0),
        start_secs: start,
        file: f.path.to_string_lossy().into_owned(),
        format: a.format.clone(),
        sample_rate: a.sample_rate as i32,
        bit_depth: a.bit_depth as i32,
        channels: a.channels as i32,
    }
}

/// `audio` is indexed like `audio_files`.
pub fn build(audio_files: &[&FileRec], audio: &[AudioInfo], cue_files: &[&FileRec]) -> DiscBuild {
    let by_rel_lower: HashMap<String, usize> = audio_files
        .iter()
        .enumerate()
        .map(|(i, f)| (f.rel.to_lowercase(), i))
        .collect();
    let mut consumed: HashSet<usize> = HashSet::new();
    let mut discs = Vec::new();
    let mut cues = Vec::new();
    let mut sheets = Vec::new();
    // Names and tags of the audio files, which a cue sheet usually repeats:
    // they tell apart legacy encodings that all decode it cleanly.
    let hints: Vec<String> = audio_files
        .iter()
        .map(|f| stem(&f.rel))
        .chain(audio.iter().flat_map(|a| {
            [&a.title, &a.artist, &a.album, &a.album_artist]
                .into_iter()
                .flatten()
                .cloned()
        }))
        .collect::<HashSet<_>>()
        .into_iter()
        .collect();

    for (ci, cf) in cue_files.iter().enumerate() {
        let decoded = match text::read_decoded_with_hints(&cf.path, &hints) {
            Ok(d) => d,
            Err(_) => continue,
        };
        let sheet = cue::parse(&decoded.text);
        let dir = parent_rel(&cf.rel);
        let mut resolved: Vec<Option<usize>> = Vec::new();
        let mut missing = Vec::new();
        for name in &sheet.files {
            let name_norm = name.replace('\\', "/");
            let rel = if dir.is_empty() {
                name_norm.clone()
            } else {
                format!("{dir}/{name_norm}")
            };
            let mut hit = by_rel_lower.get(&rel.to_lowercase()).copied();
            // Loose name: tolerates a changed extension (wav -> flac) and characters that
            // can't be used in file names ("A / B" in the cue vs "A ／ B" on disk).
            let want = loose_stem(name.rsplit('\\').next().unwrap_or(name));
            if hit.is_none() {
                hit = audio_files.iter().position(|f| {
                    parent_rel(&f.rel) == dir && loose_stem(file_name(&f.rel)) == want
                });
            }
            if hit.is_none() {
                // Cue kept in a sub folder ("cue+log/"): unique match anywhere in the album.
                let found: Vec<usize> = audio_files
                    .iter()
                    .enumerate()
                    .filter(|(_, f)| loose_stem(file_name(&f.rel)) == want)
                    .map(|(i, _)| i)
                    .collect();
                if found.len() == 1 {
                    hit = Some(found[0]);
                }
            }
            if hit.is_none() && sheet.files.len() == 1 {
                // Image named like the cue itself.
                let want = stem(&cf.rel).to_lowercase();
                hit = audio_files
                    .iter()
                    .position(|f| parent_rel(&f.rel) == dir && stem(&f.rel).to_lowercase() == want);
            }
            if hit.is_none() && sheet.files.len() == 1 && sheet.tracks.len() > 1 {
                // Renamed image: the only audio file next to the cue.
                let here: Vec<usize> = (0..audio_files.len())
                    .filter(|i| parent_rel(&audio_files[*i].rel) == dir)
                    .collect();
                if here.len() == 1 {
                    hit = Some(here[0]);
                }
            }
            if hit.is_none() {
                missing.push(name.clone());
            }
            resolved.push(hit);
        }
        cues.push(CueInfo {
            path: cf.path.to_string_lossy().into_owned(),
            encoding: decoded.encoding.clone(),
            is_utf8: decoded.is_utf8,
            missing_bom: decoded.is_utf8 && !decoded.has_bom && !decoded.text.is_ascii(),
            missing_files: missing,
        });
        let used: Vec<usize> = resolved.iter().flatten().copied().collect();
        // Duplicate cue for the same image (e.g. "x.cue" + "x (EAC).cue"): keep the first.
        if !used.is_empty() && used.iter().all(|i| consumed.contains(i)) {
            sheets.push(sheet);
            continue;
        }
        consumed.extend(used.iter().copied());

        let mut tracks = Vec::new();
        for (ti, t) in sheet.tracks.iter().enumerate() {
            let Some(Some(fi)) = resolved.get(t.file) else {
                continue;
            };
            let a = &audio[*fi];
            let next_same_file = sheet.tracks.get(ti + 1).filter(|n| n.file == t.file);
            let dur = match next_same_file {
                Some(n) => n.start - t.start,
                None => a.duration - t.start,
            };
            let title = t
                .title
                .clone()
                .unwrap_or_else(|| format!("Track {:02}", t.number));
            let artist = t.performer.clone().or_else(|| sheet.performer.clone());
            tracks.push(make_track(
                t.number,
                title,
                artist,
                dur,
                Some(t.start),
                audio_files[*fi],
                a,
            ));
        }
        let cue_name = cf.rel.rsplit('/').next().unwrap_or(&cf.rel).to_string();
        let number = sheet
            .disc_number
            .or_else(|| disc_number_from(&stem(&cf.rel)))
            .or_else(|| disc_number_from(dir.rsplit('/').next().unwrap_or("")))
            .unwrap_or(ci as i32 + 1);
        discs.push(Disc {
            number,
            label: Some(if dir.is_empty() {
                cue_name
            } else {
                format!("{dir}/{cue_name}")
            }),
            cue_path: Some(cf.path.to_string_lossy().into_owned()),
            tracks,
        });
        sheets.push(sheet);
    }

    // Loose audio files -> grouped by folder (+ disc tag).
    let mut groups: BTreeMap<(String, i32), Vec<usize>> = BTreeMap::new();
    for (i, f) in audio_files.iter().enumerate() {
        if consumed.contains(&i) {
            continue;
        }
        let dir = parent_rel(&f.rel).to_string();
        let last = dir.rsplit('/').next().unwrap_or("");
        let disc = audio[i]
            .disc
            .map(|d| d as i32)
            .or_else(|| disc_number_from(last))
            .or_else(|| {
                if DISC_LIKE.is_match(last) {
                    first_number(last)
                } else {
                    None
                }
            })
            .unwrap_or(1);
        groups.entry((dir, disc)).or_default().push(i);
    }
    for ((dir, disc), mut idx) in groups {
        idx.sort_by(|a, b| {
            let ta = audio[*a].track.unwrap_or(u32::MAX);
            let tb = audio[*b].track.unwrap_or(u32::MAX);
            ta.cmp(&tb)
                .then_with(|| natural_cmp(&audio_files[*a].rel, &audio_files[*b].rel))
        });
        let tracks = idx
            .iter()
            .enumerate()
            .map(|(pos, &i)| {
                let f = audio_files[i];
                let a = &audio[i];
                let name = stem(&f.rel);
                let caps = LEADING_NUM.captures(&name);
                let num = a
                    .track
                    .map(|n| n as i32)
                    .or_else(|| caps.as_ref().and_then(|c| c[2].parse().ok()))
                    .unwrap_or(pos as i32 + 1);
                let title = a
                    .title
                    .clone()
                    .or_else(|| caps.as_ref().map(|c| c[3].trim().to_string()))
                    .unwrap_or(name.clone());
                make_track(num, title, a.artist.clone(), a.duration, None, f, a)
            })
            .collect();
        discs.push(Disc {
            number: disc,
            label: if dir.is_empty() { None } else { Some(dir) },
            cue_path: None,
            tracks,
        });
    }

    discs.sort_by(|a, b| {
        a.number.cmp(&b.number).then_with(|| {
            natural_cmp(
                a.label.as_deref().unwrap_or(""),
                b.label.as_deref().unwrap_or(""),
            )
        })
    });
    DiscBuild {
        discs,
        cues,
        cue_sheets: sheets,
    }
}

pub fn probe_all(audio_files: &[&FileRec]) -> Vec<AudioInfo> {
    use rayon::prelude::*;
    audio_files
        .par_iter()
        .map(|f| audio::probe(&f.path))
        .collect()
}
