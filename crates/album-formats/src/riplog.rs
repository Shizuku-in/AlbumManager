//! EAC / XLD rip log interpretation (English, Japanese and Chinese EAC UIs).

use album_model::{RipLog, RipStatus, TrackVerify};
use regex::Regex;
use std::sync::LazyLock;

static TRACK_HEADER: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\s*(?:Track|トラック|音轨|音軌)\s+(\d+)\s*$").unwrap());
static TRACK_AR_LINE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\s*(?:Track|トラック|音轨|音軌)\s+(\d+)\s+(.+)$").unwrap());
static CONFIDENCE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?:confidence|信頼度|置信度)?\s*(\d+)(?:/(\d+))?\)").unwrap());
static AR_VER: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"AR v(\d)").unwrap());
static HEX8: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"([0-9A-Fa-f]{8})\s*$").unwrap());
static CTDB_ROW: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\s*(\d+)\s*\|\s*\((\d+)/(\d+)\)\s*(.*)$").unwrap());
static CHECKSUM: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^====.*[0-9A-F]{64}.*====").unwrap());
static XLD_AR: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"->\s*(.+)$").unwrap());

fn contains_any(s: &str, needles: &[&str]) -> bool {
    needles.iter().any(|n| s.contains(n))
}

fn value_after_colon(line: &str) -> Option<String> {
    let idx = line.find([':', '：'])?;
    let v = line[idx..].trim_start_matches([':', '：']).trim();
    let v = v.split("Adapter").next().unwrap_or(v).trim();
    if v.is_empty() {
        None
    } else {
        Some(v.to_string())
    }
}

fn track_mut(tracks: &mut Vec<TrackVerify>, n: i32) -> &mut TrackVerify {
    if let Some(i) = tracks.iter().position(|t| t.number == n) {
        return &mut tracks[i];
    }
    tracks.push(TrackVerify {
        number: n,
        accurate_rip: None,
        ar_ok: None,
        copy_crc: None,
        test_crc: None,
        crc_match: None,
    });
    tracks.last_mut().unwrap()
}

const ACCURATE_WORDS: &[&str] = &["ccurately ripped", "確実に正確", "精确", "精確"];
const NEGATIVE_WORDS: &[&str] = &[
    "cannot",
    "not ",
    "may not",
    "できません",
    "存在しません",
    "无法",
    "不",
    "未",
];

pub fn parse(path: &str, text: &str, encoding: &str) -> RipLog {
    let head: String = text.lines().take(5).collect::<Vec<_>>().join("\n");
    let (ripper, version) = if let Some(i) = head.find("Exact Audio Copy") {
        let v = head[i..].split_whitespace().nth(3).map(|s| s.to_string());
        ("EAC", v)
    } else if head.contains("EAC ") || head.contains("EAC\u{3000}") {
        // EAC 0.99 and older: "EAC extraction logfile" / "EAC 取り込みログファイル".
        ("EAC", Some("≤0.99".to_string()))
    } else if let Some(i) = head.find("X Lossless Decoder version") {
        let v = head[i..].split_whitespace().nth(4).map(|s| s.to_string());
        ("XLD", v)
    } else if head.contains("SACD-Ripper") {
        ("SACD-Ripper", None)
    } else if head.contains("CUERipper") {
        ("CUERipper", None)
    } else {
        ("Unknown", None)
    };

    let mut log = RipLog {
        path: path.to_string(),
        ripper: ripper.to_string(),
        version,
        encoding: encoding.to_string(),
        drive: None,
        read_mode: None,
        status: RipStatus::Unknown,
        no_errors: None,
        accurate_rip_summary: None,
        ctdb_summary: None,
        has_checksum: false,
        tracks: Vec::new(),
    };

    let mut errors = false;
    let mut ar_all = false;
    let mut ar_none = false;
    let mut ar_some_bad = false;
    let mut in_ctdb = false;
    let (mut ctdb_ok, mut ctdb_total) = (0, 0);
    let mut section: Option<i32> = None;

    for raw in text.lines() {
        let line = raw.trim_end();
        let t = line.trim();
        if t.is_empty() {
            continue;
        }
        if CHECKSUM.is_match(t) {
            log.has_checksum = true;
            continue;
        }
        if log.drive.is_none()
            && contains_any(t, &["Used drive", "使用ドライブ", "使用驱动器", "使用光驱"])
        {
            log.drive = value_after_colon(t);
            continue;
        }
        if log.read_mode.is_none()
            && contains_any(
                t,
                &["Read mode", "読み込みモード", "读取模式", "Ripper mode"],
            )
        {
            log.read_mode = value_after_colon(t);
            continue;
        }

        // --- global verdict lines ---
        if contains_any(
            t,
            &[
                "No errors occur",
                "エラーは発生しませんでした",
                "エラーは検出されませんでした",
                "没有错误发生",
                "没有发生错误",
                "未发生错误",
            ],
        ) {
            log.no_errors.get_or_insert(true);
        } else if contains_any(
            t,
            &[
                "There were errors",
                "エラーが発生しました",
                "有错误发生",
                "发生了错误",
                "Some inconsistencies found",
            ],
        ) {
            errors = true;
            log.no_errors = Some(false);
        }
        if contains_any(t, &["Suspicious position", "疑わしい位置", "可疑位置"]) {
            errors = true;
        }
        if contains_any(
            t,
            &[
                "All tracks accurately ripped",
                "全てのトラックが正確にコピーされました",
                "所有音轨精确",
                "所有音轨均已精确",
            ],
        ) {
            ar_all = true;
        } else if contains_any(
            t,
            &[
                "None of the tracks are present",
                "どのトラックも",
                "没有任何音轨在",
            ],
        ) {
            ar_none = true;
        } else if contains_any(
            t,
            &[
                "could not be verified",
                "正確であるか確認できません",
                "无法验证",
                "未能验证",
            ],
        ) {
            ar_some_bad = true;
        }

        // --- CTDB table ---
        if t.contains("CTDB Status") {
            in_ctdb = true;
            continue;
        }
        if in_ctdb {
            if let Some(c) = CTDB_ROW.captures(t) {
                let n: i32 = c[1].parse().unwrap_or(0);
                let good = c[4].to_ascii_lowercase().contains("accurately ripped");
                ctdb_total += 1;
                if good {
                    ctdb_ok += 1;
                }
                let tv = track_mut(&mut log.tracks, n);
                let tag = format!("CTDB {}/{}", &c[2], &c[3]);
                tv.accurate_rip = Some(match tv.accurate_rip.take() {
                    Some(prev) => format!("{prev} · {tag}"),
                    None => tag,
                });
                if tv.ar_ok != Some(true) {
                    tv.ar_ok = Some(good);
                }
                continue;
            } else if !t.starts_with("Track") && !t.contains('|') {
                in_ctdb = false;
            }
        }

        // --- per-track sections ---
        if let Some(c) = TRACK_HEADER.captures(t) {
            section = c[1].parse().ok();
            continue;
        }
        if let Some(c) = TRACK_AR_LINE.captures(t) {
            let rest = &c[2];
            if rest.contains("AR v")
                || rest.contains("AccurateRip")
                || rest.contains("confidence")
                || rest.contains("database")
            {
                let n: i32 = c[1].parse().unwrap_or(0);
                let ok = contains_any(rest, ACCURATE_WORDS) && !contains_any(rest, NEGATIVE_WORDS);
                let present =
                    !contains_any(rest, &["not present", "存在しません", "没有记录", "不存在"]);
                let mut label = AR_VER
                    .captures(rest)
                    .map(|v| format!("AR v{}", &v[1]))
                    .unwrap_or_else(|| "AR".into());
                if let Some(conf) = CONFIDENCE.captures(rest) {
                    label.push_str(&format!(" ({})", &conf[1]));
                }
                let tv = track_mut(&mut log.tracks, n);
                if present {
                    tv.accurate_rip = Some(label);
                    tv.ar_ok = Some(ok);
                    if !ok {
                        ar_some_bad = true;
                    }
                }
                continue;
            }
        }
        if let Some(n) = section {
            let lower = t.to_ascii_lowercase();
            if contains_any(
                t,
                &["Test CRC", "テストCRC", "测试 CRC", "测试CRC", "(test run)"],
            ) {
                if let Some(h) = HEX8.captures(t) {
                    track_mut(&mut log.tracks, n).test_crc = Some(h[1].to_uppercase());
                }
            } else if contains_any(
                t,
                &[
                    "Copy CRC",
                    "コピーCRC",
                    "复制 CRC",
                    "复制CRC",
                    "拷贝 CRC",
                    "CRC32 hash",
                ],
            ) && !lower.contains("skip")
            {
                if let Some(h) = HEX8.captures(t) {
                    track_mut(&mut log.tracks, n).copy_crc = Some(h[1].to_uppercase());
                }
            } else if ripper == "XLD" {
                if let Some(c) = XLD_AR.captures(t) {
                    let msg = &c[1];
                    let tv = track_mut(&mut log.tracks, n);
                    if msg.starts_with("Accurately ripped") {
                        tv.accurate_rip = Some(
                            msg.trim_start_matches("Accurately ripped")
                                .trim()
                                .trim_matches(['(', ')'])
                                .to_string(),
                        );
                        tv.ar_ok = Some(true);
                    } else if msg.contains("may not be accurate") {
                        tv.ar_ok = Some(false);
                        tv.accurate_rip = Some("不一致".into());
                        ar_some_bad = true;
                    }
                }
            }
        }
    }

    for tv in log.tracks.iter_mut() {
        if let (Some(a), Some(b)) = (&tv.copy_crc, &tv.test_crc) {
            tv.crc_match = Some(a == b);
            if a != b {
                errors = true;
            }
        }
    }
    log.tracks.sort_by_key(|t| t.number);

    if ripper == "XLD" && !log.tracks.is_empty() {
        let with_ar: Vec<_> = log.tracks.iter().filter_map(|t| t.ar_ok).collect();
        if !with_ar.is_empty() && with_ar.iter().all(|b| *b) && with_ar.len() == log.tracks.len() {
            ar_all = true;
        } else if with_ar.is_empty() {
            ar_none = true;
        }
    }

    log.accurate_rip_summary = if ar_all {
        Some("全部音轨 AccurateRip 校验通过".into())
    } else if ar_some_bad {
        Some("部分音轨未能通过 AccurateRip 校验".into())
    } else if ar_none {
        Some("AccurateRip 数据库中无记录".into())
    } else {
        None
    };
    let ctdb_all = ctdb_total > 0 && ctdb_ok == ctdb_total;
    if ctdb_total > 0 {
        log.ctdb_summary = Some(format!("CTDB {ctdb_ok}/{ctdb_total} 音轨校验通过"));
    }

    log.status = if ripper == "SACD-Ripper" || ripper == "Unknown" {
        RipStatus::Unknown
    } else if errors {
        RipStatus::Error
    } else if ar_all || ctdb_all {
        RipStatus::Perfect
    } else if ar_some_bad {
        RipStatus::Warning
    } else if log.no_errors == Some(true) {
        RipStatus::Good
    } else {
        RipStatus::Unknown
    };
    log
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn japanese_eac_perfect() {
        let text = "Exact Audio Copy V1.6 from 23. October 2020\n\n使用ドライブ   : PHILIPS CDRW/DVD SCB5265   Adapter: 1  ID: 0\n読み込みモード            : セキュアモード\n\nトラック  1\n\n     コピーCRC 1234ABCD\n\nトラック  1  確実に正確にコピーしました 5)  [F9218E3E]  (AR v2)\n\n全てのトラックが正確にコピーされました\n\nエラーは発生しませんでした\n\n====  6D99B76D6A2AB28513F26A10AD0D1779DFE6F4E18A7ABBECF75302B59540BB73 ====\n";
        let log = parse("x.log", text, "UTF-16LE");
        assert_eq!(log.ripper, "EAC");
        assert_eq!(log.drive.as_deref(), Some("PHILIPS CDRW/DVD SCB5265"));
        assert_eq!(log.status, RipStatus::Perfect);
        assert!(log.has_checksum);
        assert_eq!(log.tracks[0].ar_ok, Some(true));
        assert_eq!(log.tracks[0].copy_crc.as_deref(), Some("1234ABCD"));
    }

    #[test]
    fn english_not_in_db_is_good() {
        let text = "Exact Audio Copy V1.3 from 2. September 2016\nUsed drive  : X   Adapter: 1\nRead mode               : Secure\nNone of the tracks are present in the AccurateRip database\nNo errors occurred\n";
        let log = parse("x.log", text, "UTF-8");
        assert_eq!(log.status, RipStatus::Good);
    }
}
