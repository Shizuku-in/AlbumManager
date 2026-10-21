//! Text decoding with encoding detection (cue sheets / rip logs come in
//! UTF-8, UTF-16 and legacy Shift-JIS / GBK / Big5 / EUC-KR encodings).
//!
//! Legacy encodings are chosen the way Unicue does it: an encoding only
//! qualifies when it decodes every byte cleanly, and the first qualifying one
//! in priority order wins. Statistical detectors are unreliable here because
//! a cue sheet is mostly ASCII with only a few dozen non-ASCII bytes.

use encoding_rs::{Encoding, BIG5, EUC_KR, GBK, SHIFT_JIS};

/// Shift-JIS is the strictest, so other encodings rarely pass as it; GBK's
/// byte ranges nearly cover Big5's.
const LEGACY: [&Encoding; 4] = [SHIFT_JIS, GBK, BIG5, EUC_KR];

pub struct Decoded {
    pub text: String,
    pub encoding: String,
    /// True for UTF-8 (with or without BOM) — the "good" state for cue sheets.
    pub is_utf8: bool,
    /// Started with a byte order mark.
    pub has_bom: bool,
}

pub fn decode(bytes: &[u8]) -> Decoded {
    decode_with_hints(bytes, &[])
}

/// Like [decode]; `hints` are strings expected in the text (e.g. names of the
/// audio files next to a cue sheet, or their tags) and settle which legacy
/// encoding is right when several decode the bytes cleanly.
pub fn decode_with_hints(bytes: &[u8], hints: &[String]) -> Decoded {
    if let Some((enc, bom_len)) = Encoding::for_bom(bytes) {
        let (text, _) = enc.decode_without_bom_handling(&bytes[bom_len..]);
        let name = if enc == encoding_rs::UTF_8 {
            "UTF-8 BOM".to_string()
        } else {
            enc.name().to_string()
        };
        return Decoded {
            text: text.into_owned(),
            encoding: name,
            is_utf8: enc == encoding_rs::UTF_8,
            has_bom: true,
        };
    }
    // UTF-16 LE without BOM (some XLD/EAC logs): lots of zero bytes at odd positions.
    if bytes.len() >= 4 && bytes.len() % 2 == 0 {
        let zeros_odd = bytes
            .iter()
            .skip(1)
            .step_by(2)
            .take(400)
            .filter(|b| **b == 0)
            .count();
        let sample = bytes.len().min(800) / 2;
        if sample > 0 && zeros_odd * 10 >= sample * 7 {
            let (text, _, _) = encoding_rs::UTF_16LE.decode(bytes);
            return Decoded {
                text: text.into_owned(),
                encoding: "UTF-16LE".into(),
                is_utf8: false,
                has_bom: false,
            };
        }
    }
    if let Ok(s) = std::str::from_utf8(bytes) {
        let ascii = s.is_ascii();
        return Decoded {
            text: s.to_string(),
            encoding: if ascii {
                "ASCII".into()
            } else {
                "UTF-8".into()
            },
            is_utf8: true,
            has_bom: false,
        };
    }
    let (enc, text) = match pick_legacy(bytes, hints) {
        Some(found) => found,
        None => {
            // Nothing CJK fits (e.g. a Western code page): fall back to statistics.
            let mut det = chardetng::EncodingDetector::new();
            det.feed(bytes, true);
            let enc = det.guess(None, true);
            (enc, enc.decode(bytes).0.into_owned())
        }
    };
    Decoded {
        text,
        encoding: enc.name().to_string(),
        is_utf8: false,
        has_bom: false,
    }
}

fn pick_legacy(bytes: &[u8], hints: &[String]) -> Option<(&'static Encoding, String)> {
    let mut cands: Vec<(&'static Encoding, String)> = LEGACY
        .iter()
        .filter_map(|&enc| {
            let (text, malformed) = enc.decode_without_bom_handling(bytes);
            (!malformed).then(|| (enc, text.into_owned()))
        })
        .collect();
    // GBK / Big5 read as Shift-JIS always turns up half-width katakana, which
    // real Japanese cue sheets and logs practically never use.
    if cands.len() > 1 {
        cands.retain(|(enc, text)| *enc != SHIFT_JIS || !has_halfwidth_kana(text));
    }
    if cands.len() > 1 {
        let hints: Vec<String> = hints
            .iter()
            .filter(|h| !h.is_ascii())
            .map(|h| fold(h))
            .collect();
        if !hints.is_empty() {
            let score = |text: &str| {
                let text = fold(text);
                hints.iter().filter(|h| text.contains(h.as_str())).count()
            };
            let scores: Vec<usize> = cands.iter().map(|(_, t)| score(t)).collect();
            let best = *scores.iter().max().unwrap();
            if best > 0 {
                // Ties keep priority order.
                let i = scores.iter().position(|s| *s == best).unwrap();
                return Some(cands.swap_remove(i));
            }
        }
    }
    cands.into_iter().next()
}

fn has_halfwidth_kana(text: &str) -> bool {
    text.chars().any(|c| ('\u{FF61}'..='\u{FF9F}').contains(&c))
}

/// Lowercases and evens out characters that Windows code pages and the WHATWG
/// tables map differently (file names were often made by Windows tools).
fn fold(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            '\u{FF5E}' => '\u{301C}', // ～ → 〜
            '\u{FF0D}' => '\u{2212}', // － → −
            '\u{2225}' => '\u{2016}', // ∥ → ‖
            '\u{FFE2}' => '\u{00AC}', // ￢ → ¬
            c => c,
        })
        .flat_map(char::to_lowercase)
        .collect()
}

/// Reads a file, using the names of the files next to it as hints.
pub fn read_decoded(path: &std::path::Path) -> std::io::Result<Decoded> {
    let hints: Vec<String> = path
        .parent()
        .and_then(|d| std::fs::read_dir(d).ok())
        .into_iter()
        .flatten()
        .filter_map(|e| {
            let p = e.ok()?.path();
            Some(p.file_stem()?.to_str()?.to_string())
        })
        .collect();
    read_decoded_with_hints(path, &hints)
}

pub fn read_decoded_with_hints(
    path: &std::path::Path,
    hints: &[String],
) -> std::io::Result<Decoded> {
    Ok(decode_with_hints(&std::fs::read(path)?, hints))
}
