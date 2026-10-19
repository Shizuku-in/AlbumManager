//! Drive read offsets from AccurateRip's drive list (`drive_offsets.tsv`).

use regex::Regex;
use std::collections::HashMap;
use std::sync::LazyLock;

static OFFSETS: LazyLock<HashMap<&'static str, Vec<i32>>> = LazyLock::new(|| {
    include_str!("drive_offsets.tsv")
        .lines()
        .filter(|l| !l.starts_with('#'))
        .filter_map(|l| {
            let (name, offsets) = l.split_once('\t')?;
            Some((
                name,
                offsets.split(',').filter_map(|o| o.parse().ok()).collect(),
            ))
        })
        .collect()
});

/// "(revision 1.03)" and everything after it, and punctuation.
static NOISE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)revision.*|[^\w\s]").unwrap());

/// Read offsets AccurateRip lists for the drive as named in a log
/// ("PIONEER BD-RW   BDR-X13U (revision 1.03)"); empty if it isn't listed.
pub fn known_offsets(drive: &str) -> Vec<i32> {
    // Same normalisation as the table keys; some vendors log under another name.
    let key: String = NOISE
        .replace_all(drive, "")
        .replace("JLMS", "LITEON")
        .replace("HLDTST", "LG ELECTRONICS")
        .replace("MATSHITA", "PANASONIC")
        .to_uppercase()
        .split_whitespace()
        .collect();
    OFFSETS.get(key.as_str()).cloned().unwrap_or_default()
}
