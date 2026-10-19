//! Lines of an (English or translated) EAC log.

use super::{
    ar_label, hex8, setting, track, yes_no, Facts, Gap, ReadMode, CONFIDENCE, OUTPUT_FORMAT,
    TRACK_HEADER, TRACK_SUMMARY,
};

pub fn line(f: &mut Facts, t: &str, section: &mut Option<usize>) {
    if let Some(rest) = t.strip_prefix("Exact Audio Copy ") {
        if let Some((v, _)) = rest.split_once(" from") {
            f.version = Some(v.trim_start_matches('V').trim().to_string());
        }
        return;
    }
    if let Some(v) = setting(t, "Read mode") {
        f.read_mode_text = Some(v.to_string());
        f.read_mode = match v.split_whitespace().next().unwrap_or_default() {
            "Secure" => ReadMode::Secure,
            "Paranoid" => ReadMode::Paranoid,
            "Fast" => ReadMode::Fast,
            "Burst" => ReadMode::Burst,
            _ => ReadMode::Unknown,
        };
        // EAC 0.99: "Secure with NO C2, accurate stream, disable cache".
        if v.contains(" with ") {
            f.c2.get_or_insert(!v.contains("NO C2"));
            f.accurate_stream
                .get_or_insert(!v.contains("NO accurate stream"));
            f.defeat_cache
                .get_or_insert(!v.contains("NO disable cache"));
        }
        return;
    }
    let flags: [(&str, &mut Option<bool>); 7] = [
        ("Utilize accurate stream", &mut f.accurate_stream),
        ("Defeat audio cache", &mut f.defeat_cache),
        ("Make use of C2 pointers", &mut f.c2),
        (
            "Fill up missing offset samples with silence",
            &mut f.fill_silence,
        ),
        (
            "Delete leading and trailing silent blocks",
            &mut f.delete_silence,
        ),
        ("Null samples used in CRC calculations", &mut f.null_samples),
        ("Add ID3 tag", &mut f.id3),
    ];
    for (label, slot) in flags {
        if let Some(v) = setting(t, label) {
            *slot = yes_no(v);
            return;
        }
    }
    if let Some(v) = setting(t, "Read offset correction") {
        f.read_offset = v.parse().ok();
    } else if setting(t, "Combined read/write offset correction").is_some() {
        f.combined_offset = true;
    } else if setting(t, "Normalize to").is_some() {
        f.normalize = true;
    } else if let Some(v) = setting(t, "Gap handling") {
        let v = v.to_lowercase();
        f.gap = if v.contains("not detected, thus appended to previous track") {
            Gap::AppendUndetected
        } else if v.contains("appended to next track") {
            Gap::Prepend
        } else if v.contains("left out") {
            Gap::Discard
        } else if v.contains("appended to previous track") {
            Gap::Append
        } else {
            Gap::Unknown
        };
    } else if let Some(v) = setting(t, "Used output format") {
        if let Some(m) = OUTPUT_FORMAT.find(v) {
            f.encoders = vec![m.as_str().to_lowercase()];
        }
    } else if let Some(v) = setting(t, "Command line compressor") {
        // "C:\Program Files\FLAC\flac.exe" when the format is "User Defined".
        if f.encoders.is_empty() {
            let exe = v.rsplit(['\\', '/']).next().unwrap_or(v);
            f.encoders = vec![exe.split('.').next().unwrap_or(exe).to_lowercase()];
        }
    } else if t.starts_with("Range status and errors") {
        f.range = true;
        let i = track(&mut f.tracks, 1);
        f.tracks[i].range = true;
        f.tracks[i].listed = true;
        *section = Some(i);
    } else if let Some(c) = TRACK_HEADER.captures(t) {
        let i = track(&mut f.tracks, c[1].parse().unwrap_or(0));
        f.tracks[i].listed = true;
        *section = Some(i);
    } else if let Some(c) = TRACK_SUMMARY.captures(t).filter(|c| is_ar_result(&c[2])) {
        // EAC 0.99 lists AccurateRip results after the tracks.
        let i = track(&mut f.tracks, c[1].parse().unwrap_or(0));
        ar_result(&mut f.tracks[i], &c[2]);
    } else if let Some(i) = *section {
        track_line(f, i, t);
    }
}

fn track_line(f: &mut Facts, i: usize, t: &str) {
    let tr = &mut f.tracks[i];
    if let Some(v) = t.strip_prefix("Filename ") {
        tr.filename = Some(v.trim().to_string());
    } else if t.starts_with("Suspicious position") {
        tr.suspicious += 1;
    } else if t.starts_with("Timing problem") {
        tr.timing += 1;
    } else if t.starts_with("Missing samples") {
        tr.missing_samples = true;
    } else if t.starts_with("Copy aborted") {
        tr.aborted = true;
    } else if let Some(v) = t.strip_prefix("Test CRC ") {
        tr.test_crc = hex8(v);
        f.test_and_copy = true;
    } else if let Some(v) = t
        .strip_prefix("Copy CRC ")
        .or_else(|| t.strip_prefix("CRC "))
    {
        tr.copy_crc = hex8(v);
    } else if is_ar_result(t) {
        ar_result(tr, t);
    }
}

fn is_ar_result(t: &str) -> bool {
    let t = t.to_lowercase();
    t.contains("accurately ripped")
        || t.contains("cannot be verified as accurate")
        || t.contains("not present in")
}

fn ar_result(tr: &mut super::TrackFacts, t: &str) {
    let lower = t.to_lowercase();
    if lower.contains("not present in") {
        return;
    }
    tr.ar_ok = Some(lower.contains("accurately ripped"));
    tr.ar_confidence = CONFIDENCE.captures(t).and_then(|c| c[1].parse().ok());
    tr.labels.push(ar_label(t));
}
