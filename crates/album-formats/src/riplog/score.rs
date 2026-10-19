//! OPS log checker deductions (points as in cambia's OPS evaluator).

use super::{Facts, Gap, ReadMode, Ripper, TrackFacts};
use album_model::LogDeduction;

/// id, label, points (counters: per error, at most 10 errors), counts as a
/// problem by default, is a rip error (always makes the log an error).
type Kind = (&'static str, &'static str, i32, bool, bool);

pub const KINDS: &[Kind] = &[
    ("virtual_drive", "使用了虚拟光驱", 20, true, false),
    ("null_drive", "光驱信息为空", 20, true, false),
    (
        "wrong_offset",
        "读取偏移与 AccurateRip 驱动器数据库不符",
        5,
        true,
        false,
    ),
    (
        "zero_offset_unknown_drive",
        "光驱不在数据库中，且读取偏移为 0",
        5,
        true,
        false,
    ),
    ("cache_not_defeated", "未禁用音频缓存", 10, true, false),
    ("old_eac", "EAC 版本低于 0.99", 30, true, false),
    ("mp3", "MP3 抓轨日志", 100, true, false),
    (
        "combined_offset",
        "使用了读写合并偏移，无法核对读取偏移",
        4,
        true,
        false,
    ),
    ("not_secure", "未使用安全模式", 20, true, false),
    ("no_accurate_stream", "未使用精确流", 20, true, false),
    ("c2", "使用了 C2 指针", 10, true, false),
    (
        "no_fill_silence",
        "未用静音填充缺失的偏移采样",
        5,
        true,
        false,
    ),
    ("silence_deleted", "删除了首尾静音块", 5, true, false),
    ("no_null_samples", "CRC 计算未使用空采样", 5, true, false),
    ("normalized", "使用了音量标准化", 100, true, false),
    (
        "wrong_gap",
        "间隙处理方式不正确（应附加到前一音轨）",
        10,
        true,
        false,
    ),
    (
        "not_secure_crc_mismatch",
        "非安全模式下测试与复制 CRC 不一致",
        20,
        true,
        false,
    ),
    (
        "not_secure_no_test",
        "非安全模式且未使用测试和复制",
        40,
        true,
        false,
    ),
    ("range_rip", "范围抓取（未按音轨抓取）", 30, false, false),
    ("no_test_and_copy", "未使用测试和复制", 10, false, false),
    (
        "id3_on_lossless",
        "为非 MP3 文件添加了 ID3 标签",
        1,
        false,
        false,
    ),
    ("unknown_drive", "无法确认使用的光驱", 1, false, false),
    ("unknown_media", "无法确认光盘类型", 1, false, false),
    ("unknown_read_mode", "无法确认读取模式", 1, false, false),
    (
        "unknown_accurate_stream",
        "无法确认是否使用精确流",
        20,
        false,
        false,
    ),
    ("unknown_cache", "无法确认是否禁用音频缓存", 1, false, false),
    ("unknown_c2", "无法确认是否使用 C2 指针", 1, false, false),
    ("unknown_offset", "无法确认读取偏移", 1, false, false),
    (
        "unknown_fill_silence",
        "无法确认是否用静音填充缺失的偏移采样",
        1,
        false,
        false,
    ),
    (
        "unknown_silent_blocks",
        "无法确认是否删除了首尾静音块",
        1,
        false,
        false,
    ),
    ("unknown_gap", "无法确认间隙处理方式", 10, false, false),
    (
        "unknown_id3",
        "无法确认是否添加了 ID3 标签",
        1,
        false,
        false,
    ),
    (
        "unknown_filename",
        "无法确认文件名或扩展名",
        1,
        false,
        false,
    ),
    ("suspicious", "存在可疑位置", 20, true, true),
    ("timing", "存在时序问题", 20, true, true),
    ("missing_samples", "存在缺失的采样", 20, true, true),
    ("aborted", "复制被中止", 100, true, true),
    ("crc_mismatch", "测试与复制 CRC 不一致", 30, true, true),
    ("read_errors", "读取错误", 1, true, true),
    ("skipped_errors", "跳过的错误", 1, true, true),
    ("damaged_sectors", "损坏扇区", 1, true, true),
    ("inconsistent_sectors", "错误扇区不一致", 1, true, true),
];

fn deduction(id: &str, track: Option<i32>, count: Option<u32>) -> LogDeduction {
    let &(id, label, points, problem, _) = KINDS.iter().find(|k| k.0 == id).unwrap();
    let (message, points) = match count {
        Some(n) => (format!("{label} {n} 处"), n.min(10) as i32 * points),
        None => (label.to_string(), points),
    };
    LogDeduction {
        kind: id.into(),
        message,
        points,
        track,
        informational: !problem,
    }
}

/// Rip errors make a log an error whatever the user's rules say.
pub fn is_error(kind_id: &str) -> bool {
    KINDS.iter().any(|k| k.0 == kind_id && k.4)
}

pub fn deductions(f: &Facts) -> Vec<LogDeduction> {
    let eac = f.ripper == Ripper::Eac;
    let xld = f.ripper == Ripper::Xld;
    let secure = f.read_mode == ReadMode::Secure;
    // XLD's CDParanoia mode counts as secure for the not-secure checks.
    let secure_enough = secure || (xld && f.read_mode == ReadMode::Paranoid);
    let aborted = f.tracks.iter().any(|t| t.aborted);
    let drive = f.drive.as_deref().unwrap_or_default().to_lowercase();
    let offset_listed = !f.drive_offsets.is_empty();

    let release = [
        (
            "virtual_drive",
            drive.contains("generic dvd-rom scsi cdrom device"),
        ),
        ("null_drive", drive.contains("(null) (null)")),
        (
            "wrong_offset",
            offset_listed && f.read_offset.is_some_and(|o| !f.drive_offsets.contains(&o)),
        ),
        (
            "zero_offset_unknown_drive",
            !offset_listed && f.read_offset == Some(0),
        ),
        ("cache_not_defeated", f.defeat_cache == Some(false)),
        (
            "old_eac",
            eac && f.version.as_deref().is_none_or(|v| v < "0.99"),
        ),
        ("mp3", f.mp3_only),
        ("combined_offset", f.combined_offset),
        ("not_secure", eac && !secure),
        ("no_accurate_stream", f.accurate_stream == Some(false)),
        ("c2", f.c2 == Some(true)),
        ("no_fill_silence", f.fill_silence == Some(false)),
        ("silence_deleted", f.delete_silence == Some(true)),
        ("no_null_samples", f.null_samples == Some(false)),
        ("normalized", f.normalize),
        (
            "wrong_gap",
            !matches!(f.gap, Gap::Unknown | Gap::Append | Gap::AppendNoHtoa),
        ),
        (
            "not_secure_crc_mismatch",
            !secure_enough && f.tracks.iter().any(TrackFacts::crc_mismatch),
        ),
        (
            "not_secure_no_test",
            !secure_enough && !aborted && !f.test_and_copy,
        ),
        ("range_rip", eac && f.range),
        ("no_test_and_copy", !aborted && !f.test_and_copy),
        ("id3_on_lossless", f.id3 == Some(true) && !f.mp3_only),
        ("unknown_drive", f.drive.is_none()),
        (
            "unknown_media",
            xld && f.version.as_deref().is_some_and(|v| v >= "20130127") && f.media.is_none(),
        ),
        ("unknown_read_mode", f.read_mode == ReadMode::Unknown),
        (
            "unknown_accurate_stream",
            secure && f.accurate_stream.is_none(),
        ),
        ("unknown_cache", secure && f.defeat_cache.is_none()),
        ("unknown_c2", secure && f.c2.is_none()),
        ("unknown_offset", f.read_offset.is_none()),
        ("unknown_fill_silence", eac && f.fill_silence.is_none()),
        ("unknown_silent_blocks", eac && f.delete_silence.is_none()),
        ("unknown_gap", f.gap == Gap::Unknown),
        ("unknown_id3", eac && f.id3.is_none()),
    ];
    let mut out: Vec<LogDeduction> = release
        .into_iter()
        .filter(|r| r.1)
        .map(|(id, _)| deduction(id, None, None))
        .collect();

    // Summary-only entries (EAC's AccurateRip / CTDB lists) aren't rip results.
    for t in f.tracks.iter().filter(|t| t.listed) {
        let ext_ok = t.filename.as_deref().is_some_and(|n| {
            let n = n.to_lowercase();
            n.ends_with(".wav") || n.ends_with(".flac") || n.ends_with(".ape") || n.len() >= 243
        });
        let n = Some(t.number);
        let checks = [
            (
                "unknown_filename",
                t.filename.is_none() || (eac && !t.range && !ext_ok),
            ),
            (
                "suspicious",
                (eac && t.suspicious > 0) || (xld && t.inconsistent > 0),
            ),
            ("timing", eac && t.timing > 0),
            ("missing_samples", t.missing_samples),
            ("aborted", t.aborted),
            ("crc_mismatch", t.crc_mismatch()),
        ];
        out.extend(
            checks
                .into_iter()
                .filter(|c| c.1)
                .map(|(id, _)| deduction(id, n, None)),
        );
        let counters = [
            ("read_errors", t.read_errors),
            ("skipped_errors", t.skipped),
            ("damaged_sectors", t.damaged),
            ("inconsistent_sectors", t.inconsistent),
        ];
        out.extend(
            counters
                .into_iter()
                .filter(|c| xld && c.1 > 0)
                .map(|(id, count)| deduction(id, n, Some(count))),
        );
    }
    out
}
