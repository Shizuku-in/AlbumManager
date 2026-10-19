//! Plain data types describing an album library. Shared by the scanner and
//! the Flutter bridge (flutter_rust_bridge generates the Dart classes from them).

use serde::{Deserialize, Serialize};

/// Where an album came from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AlbumSource {
    /// Ripped from a physical CD (has a rip log or a cue + image).
    CdRip,
    /// Downloaded / purchased digital release.
    Digital,
    /// Disc image or BD/DVD structure (ISO, BDMV, m2ts...).
    DiscImage,
    Unknown,
}

/// Audio quality tier, derived from the best stream in the album.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AudioQuality {
    Lossy,
    /// CD quality lossless (<= 48 kHz, 16 bit).
    Lossless,
    /// > 48 kHz or >= 24 bit PCM.
    HiRes,
    Dsd,
    Unknown,
}

/// Overall verdict of the rip logs of an album.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RipStatus {
    /// Not a CD rip.
    NotApplicable,
    /// CD rip without any log.
    NoLog,
    /// No errors, every track verified by AccurateRip / CTDB.
    Perfect,
    /// No errors, but not (fully) verifiable.
    Good,
    /// Some tracks could not be verified / mismatched.
    Warning,
    /// Read errors / suspicious positions.
    Error,
    /// Log exists but could not be interpreted (e.g. SACD logs).
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum IssueKind {
    MissingCover,
    /// CUE sheet is not UTF-8 (Shift-JIS / GBK ...) — fixable.
    CueEncoding,
    /// CUE references a file that does not exist.
    CueMissingFile,
    RipErrors,
    RipUnverified,
    MissingLog,
    /// Folder name does not follow "[YYMMDD] Title".
    NonStandardName,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Issue {
    pub kind: IssueKind,
    pub message: String,
    pub path: Option<String>,
}

/// Lightweight album info used by grids, lists and statistics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlbumSummary {
    /// Path relative to the library root, used as stable id.
    pub id: String,
    pub path: String,
    pub folder_name: String,
    pub title: String,
    pub artist: Option<String>,
    /// "YYYY-MM-DD" when known.
    pub date: Option<String>,
    pub year: Option<i32>,
    pub genre: Option<String>,
    pub source: AlbumSource,
    pub quality: AudioQuality,
    /// e.g. "FLAC · 24bit / 96kHz"
    pub quality_label: String,
    pub formats: Vec<String>,
    pub sample_rate: i32,
    pub bit_depth: i32,
    pub disc_count: i32,
    pub track_count: i32,
    pub duration_secs: f64,
    pub total_size: i64,
    pub audio_size: i64,
    pub image_count: i32,
    /// Booklet / disc scans present (detected by [ScanRules], or set by hand).
    #[serde(default)]
    pub has_scans: bool,
    pub has_cue: bool,
    pub has_log: bool,
    pub rip_status: RipStatus,
    pub cover_path: Option<String>,
    pub cover_thumb: Option<String>,
    /// Dominant cover color as 0xAARRGGBB.
    pub accent_color: Option<u32>,
    /// Unix seconds; folder creation time ("added to library").
    pub added_at: i64,
    pub modified_at: i64,
    pub issues: Vec<Issue>,
    /// Values the user set by hand; they take precedence over detection.
    #[serde(default)]
    pub overrides: AlbumOverride,
}

/// User-editable recognition rules, stored with the library config.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScanRules {
    /// Cover image file name prefixes, highest priority first.
    pub cover_keywords: Vec<String>,
    /// Album folder name templates using `{date}`, `{year}` and `{title}`,
    /// tried in order.
    pub name_templates: Vec<String>,
    /// An album has scans when an image sits in a subfolder whose name
    /// contains one of these words (case-insensitive)...
    #[serde(default = "default_scan_folder_keywords")]
    pub scan_folder_keywords: Vec<String>,
    /// ...or when it has at least this many images (0 = never by count).
    #[serde(default = "default_scan_min_images")]
    pub scan_min_images: u32,
}

fn default_scan_folder_keywords() -> Vec<String> {
    [
        "scan",
        "bk",
        "booklet",
        "artwork",
        "扫图",
        "掃圖",
        "スキャン",
    ]
    .map(String::from)
    .to_vec()
}

fn default_scan_min_images() -> u32 {
    5
}

impl Default for ScanRules {
    fn default() -> Self {
        Self {
            cover_keywords: [
                "cover",
                "folder",
                "front",
                "jacket",
                "album",
                "ジャケット",
                "封面",
            ]
            .map(String::from)
            .to_vec(),
            name_templates: vec!["[{date}] {title}".into()],
            scan_folder_keywords: default_scan_folder_keywords(),
            scan_min_images: default_scan_min_images(),
        }
    }
}

/// Hand-edited album values, kept apart from the scan results so a rescan
/// re-applies them. `None` = use the detected value.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct AlbumOverride {
    pub source: Option<AlbumSource>,
    /// An image file of the album to use as cover.
    pub cover_path: Option<String>,
    pub has_scans: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Track {
    pub number: i32,
    pub title: String,
    pub artist: Option<String>,
    pub duration_secs: f64,
    /// Start offset inside the image file (cue rips only).
    pub start_secs: Option<f64>,
    pub file: String,
    pub format: String,
    pub sample_rate: i32,
    pub bit_depth: i32,
    pub channels: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Disc {
    pub number: i32,
    /// Sub folder name or cue file name, if any.
    pub label: Option<String>,
    pub cue_path: Option<String>,
    pub tracks: Vec<Track>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackVerify {
    pub number: i32,
    /// e.g. "AR v2 (5)", "CTDB 84/84"
    pub accurate_rip: Option<String>,
    /// Verified by AccurateRip or CTDB.
    pub ar_ok: Option<bool>,
    /// AccurateRip alone: matched / didn't match.
    pub accurate_rip_ok: Option<bool>,
    /// AccurateRip confidence: matching submissions, or for a mismatch the
    /// submissions of the pressing in the database.
    pub ar_confidence: Option<i32>,
    pub ctdb_ok: Option<bool>,
    pub copy_crc: Option<String>,
    pub test_crc: Option<String>,
    pub crc_match: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RipLog {
    pub path: String,
    /// "EAC", "XLD", "SACD-Ripper", "Unknown"
    pub ripper: String,
    pub version: Option<String>,
    pub encoding: String,
    pub drive: Option<String>,
    pub read_mode: Option<String>,
    /// Judged with the user's [RipRules]; see `errors` for the log's own verdict.
    pub status: RipStatus,
    pub no_errors: Option<bool>,
    /// Read errors, suspicious positions, CRC mismatches or aborted copies.
    pub errors: bool,
    /// "全部 AccurateRip 校验通过" etc. (human readable)
    pub accurate_rip_summary: Option<String>,
    pub ctdb_summary: Option<String>,
    pub checksum: LogChecksum,
    /// OPS-style score: 100 minus the deductions. None for logs that aren't
    /// scored (SACD-Ripper, unknown rippers).
    pub score: Option<i32>,
    pub deductions: Vec<LogDeduction>,
    /// EAC UI language the log was written in ("日本語"), when it had to be
    /// translated to English for checking.
    pub language: Option<String>,
    pub read_offset: Option<i32>,
    /// Read offsets AccurateRip lists for the drive; empty if it isn't known.
    pub drive_offsets: Vec<i32>,
    pub tracks: Vec<TrackVerify>,
}

/// The signature EAC / XLD append to their logs, which detects later edits.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LogChecksum {
    Valid,
    /// The log was changed after ripping.
    Invalid,
    Missing,
    /// The ripper doesn't sign its logs.
    NotApplicable,
}

/// One OPS log checker deduction.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogDeduction {
    /// Stable id of the rule (see [DeductionKind]).
    pub kind: String,
    pub message: String,
    pub points: i32,
    /// Track-level deductions name their track.
    pub track: Option<i32>,
    /// Counts in the score but, per the user's [RipRules], isn't a problem
    /// with the rip, so it doesn't flag the log.
    pub informational: bool,
}

/// A log checker rule the user can count as a problem or not.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeductionKind {
    pub id: String,
    pub label: String,
    pub points: i32,
    pub problem_by_default: bool,
}

/// How rip logs are judged. Applied to the parsed logs without reading them
/// again, so changes take effect immediately.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RipRules {
    /// Deduction kinds that flag a log; the others only count in the score.
    pub problem_kinds: Vec<String>,
    /// An AccurateRip mismatch flags a log when the database has at least
    /// this many submissions for the disc (0 = never).
    pub ar_mismatch_min_submissions: u32,
    pub invalid_signature_is_problem: bool,
    /// "Perfect" needs every track matched by AccurateRip with at least this
    /// confidence (or by CTDB)...
    pub perfect_min_confidence: u32,
    /// ...and, when the log has CTDB results, by CTDB as well.
    pub perfect_needs_both: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CueInfo {
    pub path: String,
    pub encoding: String,
    pub is_utf8: bool,
    pub missing_files: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageItem {
    pub path: String,
    /// Relative folder inside the album ("" for root).
    pub group: String,
    pub size: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileEntry {
    pub rel_path: String,
    pub size: i64,
}

/// Full album info for the detail page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Album {
    pub summary: AlbumSummary,
    pub discs: Vec<Disc>,
    pub logs: Vec<RipLog>,
    pub cues: Vec<CueInfo>,
    pub images: Vec<ImageItem>,
    /// Every file of the album folder.
    pub files: Vec<FileEntry>,
    /// Fingerprint of the folder contents (for incremental rescans).
    pub fingerprint: u64,
}
