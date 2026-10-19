//! Rip log checking. EAC / XLD logs are read into the settings and per-track
//! results that matter (logs from EAC's Japanese / Chinese UIs are translated
//! to English first) and scored with the OPS log checker's deductions. The
//! rules, phrase table, drive offsets and signature algorithms were learned
//! from cambia (MIT, https://github.com/rokkhonorg/cambia; see LICENSE-cambia).

mod drives;
mod eac;
mod judge;
mod lang;
mod score;
mod sign;
mod xld;

pub use judge::{deduction_kinds, default_rules, judge, problems};
pub use lang::translate;

use album_model::{LogChecksum, RipLog, RipStatus, TrackVerify};
use regex::Regex;
use std::borrow::Cow;
use std::sync::LazyLock;

#[derive(Clone, Copy, PartialEq, Eq, Default)]
enum Ripper {
    #[default]
    Unknown,
    Eac,
    Xld,
    Sacd,
    CueRipper,
}

#[derive(Clone, Copy, PartialEq, Eq, Default)]
enum ReadMode {
    Secure,
    Paranoid,
    Fast,
    Burst,
    #[default]
    Unknown,
}

#[derive(Clone, Copy, PartialEq, Eq, Default)]
enum Gap {
    Append,
    AppendNoHtoa,
    AppendUndetected,
    Prepend,
    Discard,
    #[default]
    Unknown,
}

/// What the scorer looks at; `None` = the log doesn't say.
#[derive(Default)]
struct Facts {
    ripper: Ripper,
    version: Option<String>,
    drive: Option<String>,
    drive_offsets: Vec<i32>,
    media: Option<String>,
    read_mode_text: Option<String>,
    read_mode: ReadMode,
    accurate_stream: Option<bool>,
    defeat_cache: Option<bool>,
    c2: Option<bool>,
    read_offset: Option<i32>,
    combined_offset: bool,
    fill_silence: Option<bool>,
    delete_silence: Option<bool>,
    null_samples: Option<bool>,
    gap: Gap,
    normalize: bool,
    id3: Option<bool>,
    test_and_copy: bool,
    range: bool,
    /// Output formats ("flac", "mp3") from the encoder settings / file names.
    encoders: Vec<String>,
    mp3_only: bool,
    tracks: Vec<TrackFacts>,
}

#[derive(Default)]
struct TrackFacts {
    number: i32,
    /// Has its own "Track N" / range section (not just a line in EAC's
    /// AccurateRip or CTDB summary).
    listed: bool,
    range: bool,
    filename: Option<String>,
    aborted: bool,
    /// EAC suspicious positions.
    suspicious: u32,
    timing: u32,
    missing_samples: bool,
    // XLD error counters.
    read_errors: u32,
    skipped: u32,
    damaged: u32,
    inconsistent: u32,
    test_crc: Option<String>,
    copy_crc: Option<String>,
    ar_ok: Option<bool>,
    /// See [TrackVerify::ar_confidence].
    ar_confidence: Option<i32>,
    ctdb_ok: Option<bool>,
    /// "AR v2 (5)", "CTDB 84/84", ...
    labels: Vec<String>,
}

impl TrackFacts {
    fn crc_mismatch(&self) -> bool {
        matches!((&self.test_crc, &self.copy_crc), (Some(a), Some(b)) if a != b)
    }

    fn has_errors(&self) -> bool {
        self.crc_mismatch()
            || self.aborted
            || self.missing_samples
            || self.suspicious
                + self.timing
                + self.read_errors
                + self.skipped
                + self.damaged
                + self.inconsistent
                > 0
    }
}

macro_rules! regex {
    ($name:ident, $re:literal) => {
        static $name: LazyLock<Regex> = LazyLock::new(|| Regex::new($re).unwrap());
    };
}
regex!(TRACK_HEADER, r"^Track\s+(\d+)$");
regex!(TRACK_SUMMARY, r"^Track\s+(\d+)\s+(.+)$");
regex!(HEX8, r"^[0-9A-Fa-f]{8}");
regex!(AR_VERSION, r"AR v(\d)");
regex!(CONFIDENCE, r"confidence (\d+)");
regex!(SUBMISSIONS, r"total (\d+) submission");
regex!(CTDB_ROW, r"^(\d+)\s*\|\s*\((\d+)/(\d+)\)\s*(.*)$");
regex!(
    OUTPUT_FORMAT,
    r"(?i)\b(flac|wav|mp3|m4a|ape|tta|ogg|tak|wv)\b"
);

/// Value of a "Label   : value" line.
fn setting<'a>(line: &'a str, label: &str) -> Option<&'a str> {
    let rest = line.strip_prefix(label)?.trim_start();
    Some(
        rest.strip_prefix(':')
            .or_else(|| rest.strip_prefix('：'))?
            .trim(),
    )
}

fn yes_no(v: &str) -> Option<bool> {
    let v = v.to_ascii_lowercase();
    if v.starts_with("yes") || v.starts_with("ok") {
        Some(true)
    } else if v.starts_with("no") {
        Some(false)
    } else {
        None
    }
}

fn hex8(s: &str) -> Option<String> {
    HEX8.find(s.trim()).map(|m| m.as_str().to_uppercase())
}

fn track(tracks: &mut Vec<TrackFacts>, number: i32) -> usize {
    tracks
        .iter()
        .position(|t| t.number == number)
        .unwrap_or_else(|| {
            tracks.push(TrackFacts {
                number,
                ..Default::default()
            });
            tracks.len() - 1
        })
}

fn ar_label(text: &str) -> String {
    let mut label = AR_VERSION
        .captures(text)
        .map_or("AR".to_string(), |c| format!("AR v{}", &c[1]));
    if let Some(c) = CONFIDENCE.captures(text) {
        label.push_str(&format!(" ({})", &c[1]));
    }
    label
}

/// Reads a log file. Legacy-encoded EAC logs are checked against their
/// header line: the general detection favours Shift-JIS, so a GBK / Big5 log
/// can come out garbled and is then decoded again with the other encodings.
pub fn read(path: &std::path::Path) -> std::io::Result<crate::text::Decoded> {
    let bytes = std::fs::read(path)?;
    let decoded = crate::text::decode(&bytes);
    let legacy = !decoded.is_utf8 && !decoded.encoding.starts_with("UTF-16");
    if !legacy || !decoded.text.contains("EAC") || lang::header_recognised(&decoded.text) {
        return Ok(decoded);
    }
    for enc in [encoding_rs::GBK, encoding_rs::BIG5, encoding_rs::SHIFT_JIS] {
        let (text, _, malformed) = enc.decode(&bytes);
        if !malformed && lang::header_recognised(&text) {
            return Ok(crate::text::Decoded {
                text: text.into_owned(),
                encoding: enc.name().to_string(),
                is_utf8: false,
                has_bom: false,
            });
        }
    }
    Ok(decoded)
}

pub fn parse(path: &str, text: &str, encoding: &str) -> RipLog {
    let head: String = text.lines().take(5).collect::<Vec<_>>().join("\n");
    let ripper = if head.contains("X Lossless Decoder") {
        Ripper::Xld
    } else if head.contains("CUERipper") {
        Ripper::CueRipper
    } else if head.contains("SACD-Ripper") {
        Ripper::Sacd
    } else if head.contains("Exact Audio Copy") || head.contains("EAC") {
        Ripper::Eac
    } else {
        Ripper::Unknown
    };
    let (language, english) = match ripper {
        Ripper::Eac => match lang::translate(text) {
            Some((name, translated)) => (Some(name), Cow::Owned(translated)),
            None => (None, Cow::Borrowed(text)),
        },
        _ => (None, Cow::Borrowed(text)),
    };

    let mut f = Facts {
        ripper,
        ..Default::default()
    };
    let mut section = None;
    let (mut errors, mut no_errors) = (false, None);
    let (mut ar_all, mut ar_none) = (false, false);
    let mut in_ctdb = false;
    for line in english.lines() {
        let t = line.trim();
        if t.is_empty() {
            continue;
        }
        if let Some(v) = t.strip_prefix("Used drive") {
            // Some translations drop the colon.
            let v = v.trim_start().trim_start_matches([':', '：']);
            let v = v.split("Adapter:").next().unwrap_or(v).trim();
            if f.drive.is_none() && !v.is_empty() {
                f.drive = Some(v.to_string());
            }
            continue;
        }
        if t.contains("No errors occur") {
            no_errors.get_or_insert(true);
        } else if t.starts_with("There were errors") || t.starts_with("Some inconsistencies found")
        {
            errors = true;
            no_errors = Some(false);
        }
        if t.contains("All tracks accurately ripped") {
            ar_all = true;
        } else if t.contains("None of the tracks are present in the AccurateRip database") {
            ar_none = true;
        }
        // CTDB plugin results (EAC): "  3   | (84/84) Accurately ripped".
        if t.contains("CTDB Status") {
            in_ctdb = true;
            continue;
        }
        if in_ctdb {
            if let Some(c) = CTDB_ROW.captures(t) {
                let i = track(&mut f.tracks, c[1].parse().unwrap_or(0));
                let tr = &mut f.tracks[i];
                let good = c[4].to_ascii_lowercase().contains("accurately ripped");
                tr.labels.push(format!("CTDB {}/{}", &c[2], &c[3]));
                tr.ctdb_ok = Some(good);
                continue;
            } else if !t.starts_with("Track") && !t.contains('|') {
                in_ctdb = false;
            }
        }
        match ripper {
            Ripper::Eac => eac::line(&mut f, t, &mut section),
            Ripper::Xld => xld::line(&mut f, t, &mut section),
            _ => {}
        }
    }
    f.tracks.sort_by_key(|t| t.number);
    if let Some(d) = &f.drive {
        f.drive_offsets = drives::known_offsets(d);
    }
    if ripper == Ripper::Xld {
        f.null_samples = Some(true);
        f.accurate_stream.get_or_insert(false);
    }
    f.mp3_only = !f.encoders.is_empty()
        && f.encoders
            .iter()
            .all(|e| e.contains("mp3") || e.contains("lame"));

    let scored = matches!(ripper, Ripper::Eac | Ripper::Xld);
    let checksum = match ripper {
        Ripper::Eac => sign::eac(text),
        Ripper::Xld => sign::xld(text),
        _ => LogChecksum::NotApplicable,
    };
    let deductions = if scored {
        score::deductions(&f)
    } else {
        Vec::new()
    };
    let score = scored.then(|| 100 - deductions.iter().map(|d| d.points).sum::<i32>());

    let with_ar: Vec<bool> = f.tracks.iter().filter_map(|t| t.ar_ok).collect();
    let ar_bad = with_ar.iter().filter(|ok| !**ok).count();
    if !with_ar.is_empty() && ar_bad == 0 && with_ar.len() == f.tracks.len() {
        ar_all = true;
    }
    let ctdb: Vec<bool> = f.tracks.iter().filter_map(|t| t.ctdb_ok).collect();

    let errors = errors || f.tracks.iter().any(TrackFacts::has_errors);

    let mut log = RipLog {
        path: path.to_string(),
        ripper: match ripper {
            Ripper::Eac => "EAC",
            Ripper::Xld => "XLD",
            Ripper::Sacd => "SACD-Ripper",
            Ripper::CueRipper => "CUERipper",
            Ripper::Unknown => "Unknown",
        }
        .to_string(),
        version: f
            .version
            .clone()
            .or_else(|| (ripper == Ripper::Eac).then(|| "0.99 之前".to_string())),
        encoding: encoding.to_string(),
        drive: f.drive.clone(),
        read_mode: f.read_mode_text.clone(),
        // Set by judge() below.
        status: RipStatus::Unknown,
        no_errors,
        errors,
        accurate_rip_summary: if ar_all {
            Some("全部音轨 AccurateRip 校验通过".into())
        } else if ar_bad > 0 && ar_bad == with_ar.len() {
            Some("全部音轨与 AccurateRip 数据库不一致".into())
        } else if ar_bad > 0 {
            Some(format!("{ar_bad} 条音轨与 AccurateRip 数据库不一致"))
        } else if ar_none || (ripper == Ripper::Xld && with_ar.is_empty() && !f.tracks.is_empty()) {
            Some("AccurateRip 数据库中无记录".into())
        } else {
            None
        },
        ctdb_summary: (!ctdb.is_empty()).then(|| {
            format!(
                "CTDB {}/{} 音轨校验通过",
                ctdb.iter().filter(|ok| **ok).count(),
                ctdb.len()
            )
        }),
        checksum,
        score,
        deductions,
        language: language.map(str::to_string),
        read_offset: f.read_offset,
        drive_offsets: f.drive_offsets.clone(),
        tracks: f
            .tracks
            .iter()
            .map(|t| TrackVerify {
                number: t.number,
                accurate_rip: (!t.labels.is_empty()).then(|| t.labels.join(" · ")),
                ar_ok: match (t.ar_ok, t.ctdb_ok) {
                    (Some(true), _) | (_, Some(true)) => Some(true),
                    (a, c) => a.or(c),
                },
                accurate_rip_ok: t.ar_ok,
                ar_confidence: t.ar_confidence,
                ctdb_ok: t.ctdb_ok,
                copy_crc: t.copy_crc.clone(),
                test_crc: t.test_crc.clone(),
                crc_match: match (&t.test_crc, &t.copy_crc) {
                    (Some(a), Some(b)) => Some(a == b),
                    _ => None,
                },
            })
            .collect(),
    };
    judge(&mut log, &default_rules());
    log
}
