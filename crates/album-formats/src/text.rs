//! Text decoding with encoding detection (cue sheets / rip logs come in
//! UTF-8, UTF-16 and legacy Shift-JIS / GBK / Big5 encodings).

pub struct Decoded {
    pub text: String,
    pub encoding: String,
    /// True for UTF-8 (with or without BOM) — the "good" state for cue sheets.
    pub is_utf8: bool,
    /// Started with a byte order mark.
    pub has_bom: bool,
}

pub fn decode(bytes: &[u8]) -> Decoded {
    if let Some((enc, bom_len)) = encoding_rs::Encoding::for_bom(bytes) {
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
    let mut det = chardetng::EncodingDetector::new();
    det.feed(bytes, true);
    // Music in this kind of library is mostly Japanese; bias towards it.
    let enc = det.guess(Some(b"jp"), true);
    let (text, _, _) = enc.decode(bytes);
    Decoded {
        text: text.into_owned(),
        encoding: enc.name().to_string(),
        is_utf8: false,
        has_bom: false,
    }
}

pub fn read_decoded(path: &std::path::Path) -> std::io::Result<Decoded> {
    Ok(decode(&std::fs::read(path)?))
}
