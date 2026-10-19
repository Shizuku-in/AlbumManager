//! Lines of an XLD log.

use super::{
    ar_label, hex8, setting, track, yes_no, Facts, Gap, ReadMode, CONFIDENCE, OUTPUT_FORMAT,
    SUBMISSIONS, TRACK_HEADER,
};

pub fn line(f: &mut Facts, t: &str, section: &mut Option<usize>) {
    if let Some(v) = t.strip_prefix("X Lossless Decoder version ") {
        f.version = v.split_whitespace().next().map(str::to_string);
    } else if let Some(v) = setting(t, "Media type") {
        f.media = Some(v.to_string());
    } else if let Some(v) = setting(t, "Ripper mode") {
        f.read_mode_text = Some(v.to_string());
        f.read_mode = if v == "XLD Secure Ripper" {
            ReadMode::Secure
        } else if v.contains("CDParanoia") {
            ReadMode::Paranoid
        } else if v == "Burst" {
            ReadMode::Burst
        } else {
            ReadMode::Unknown
        };
    } else if let Some(v) = setting(t, "Use cdparanoia mode") {
        f.read_mode_text = Some(format!("CDParanoia: {v}"));
        f.read_mode = if v.contains("YES") {
            ReadMode::Paranoid
        } else {
            ReadMode::Burst
        };
    } else if let Some(v) = setting(t, "Disable audio cache") {
        f.defeat_cache = yes_no(v);
    } else if let Some(v) = setting(t, "Make use of C2 pointers") {
        f.c2 = yes_no(v);
    } else if let Some(v) = setting(t, "Read offset correction") {
        f.read_offset = v.parse().ok();
    } else if let Some(v) = setting(t, "Gap status") {
        f.gap = match v {
            "Analyzed, Appended (except HTOA)" => Gap::AppendNoHtoa,
            "Analyzed, Appended" => Gap::Append,
            _ => Gap::Unknown,
        };
    } else if let Some(c) = TRACK_HEADER.captures(t) {
        let i = track(&mut f.tracks, c[1].parse().unwrap_or(0));
        f.tracks[i].listed = true;
        *section = Some(i);
    } else if let Some(i) = *section {
        track_line(f, i, t);
    }
}

fn track_line(f: &mut Facts, i: usize, t: &str) {
    let tr = &mut f.tracks[i];
    let count = |v: &str| v.parse::<u32>().unwrap_or(0);
    if let Some(v) = setting(t, "Filename") {
        if let Some(m) = OUTPUT_FORMAT.find(v.rsplit('.').next().unwrap_or_default()) {
            f.encoders.push(m.as_str().to_lowercase());
        }
        tr.filename = Some(v.to_string());
    } else if let Some(v) = setting(t, "CRC32 hash (test run)") {
        tr.test_crc = hex8(v);
        f.test_and_copy = true;
    } else if let Some(v) = setting(t, "CRC32 hash") {
        tr.copy_crc = hex8(v);
    } else if t.starts_with("AccurateRip") && t.contains("signature") {
        // Only written when AccurateRip is used.
        f.accurate_stream = Some(true);
    } else if let Some(v) = setting(t, "Read error") {
        tr.read_errors = count(v);
    } else if let Some(v) = setting(t, "Skipped (treated as error)") {
        tr.skipped = count(v);
    } else if let Some(v) = setting(t, "Damaged sector count") {
        tr.damaged = count(v);
    } else if let Some(v) = setting(t, "Inconsistency in error sectors") {
        tr.inconsistent = count(v);
    } else if t.starts_with("Missing samples") {
        tr.missing_samples = true;
    } else if let Some(msg) = t.strip_prefix("->") {
        if msg.starts_with("Accurately ripped") {
            tr.ar_ok = Some(true);
            tr.ar_confidence = CONFIDENCE.captures(msg).and_then(|c| c[1].parse().ok());
            tr.labels.push(ar_label(msg));
        } else if msg.contains("may not be accurate") {
            tr.ar_ok = Some(false);
            tr.ar_confidence = SUBMISSIONS.captures(msg).and_then(|c| c[1].parse().ok());
            tr.labels.push("AR 不一致".into());
        }
    }
}
