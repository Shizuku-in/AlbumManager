//! Turns an album folder into an `Album` (summary + details).

use album_formats::audio::{self, is_audio_ext, AudioInfo, LOSSY_EXTS};
use super::discover::{list_files, FileRec};
use crate::imaging::{self, is_image_ext};
use crate::rules::{self, Rules};
use crate::util::{natural_cmp, unix_secs};
use super::discs;
use album_formats::{riplog, text};
use album_model::*;
use regex::Regex;
use std::collections::HashMap;
use std::path::Path;
use std::sync::LazyLock;

pub const COVER_THUMB: u32 = 480;
static SCAN_COVER_NAME: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)(cover|front|jacket|ジャケ|表|封面|^0*1\b|_0*1$|^0*1$)").unwrap());

fn most_common<'a>(it: impl Iterator<Item = &'a str>) -> Option<(String, usize)> {
    let mut m: HashMap<&str, usize> = HashMap::new();
    let mut total = 0;
    for s in it {
        *m.entry(s).or_default() += 1;
        total += 1;
    }
    let _ = total;
    m.into_iter().max_by(|a, b| a.1.cmp(&b.1).then(b.0.cmp(a.0))).map(|(k, v)| (k.to_string(), v))
}

fn severity(s: RipStatus) -> u8 {
    match s {
        RipStatus::Error => 6,
        RipStatus::Warning => 5,
        RipStatus::Unknown => 4,
        RipStatus::Good => 3,
        RipStatus::Perfect => 2,
        RipStatus::NoLog => 1,
        RipStatus::NotApplicable => 0,
    }
}

fn format_rate(rate: u32) -> String {
    let k = rate as f64 / 1000.0;
    if (k - k.round()).abs() < 0.01 { format!("{}kHz", k.round()) } else { format!("{k:.1}kHz") }
}

fn quality_label(audio_files: &[&FileRec], infos: &[AudioInfo]) -> String {
    // Primary format = most bytes.
    let mut bytes: HashMap<&str, u64> = HashMap::new();
    for (f, a) in audio_files.iter().zip(infos) {
        *bytes.entry(a.format.as_str()).or_default() += f.size;
    }
    let Some((fmt, _)) = bytes.into_iter().max_by_key(|(_, b)| *b) else { return String::new() };
    let of_fmt: Vec<&AudioInfo> = infos.iter().filter(|a| a.format == fmt).collect();
    let rate = of_fmt.iter().map(|a| a.sample_rate).max().unwrap_or(0);
    if of_fmt.iter().any(|a| a.is_dsd) {
        return if rate > 0 { format!("{fmt} · DSD{}", rate / 44100) } else { format!("{fmt} · DSD") };
    }
    if LOSSY_EXTS.contains(&fmt.to_ascii_lowercase().as_str()) {
        let br = of_fmt.iter().map(|a| a.bitrate_kbps).max().unwrap_or(0);
        return if br > 0 { format!("{fmt} · {br}kbps") } else { fmt.to_string() };
    }
    let bits = of_fmt.iter().map(|a| a.bit_depth).max().unwrap_or(0);
    match (bits, rate) {
        (0, 0) => fmt.to_string(),
        (0, r) => format!("{fmt} · {}", format_rate(r)),
        (b, r) => format!("{fmt} · {b}bit / {}", format_rate(r)),
    }
}

fn file_name(f: &FileRec) -> &str {
    f.rel.rsplit('/').next().unwrap_or("")
}

fn pick_cover<'a>(images: &[&'a FileRec], rules: &Rules) -> Option<&'a FileRec> {
    let root: Vec<_> = images.iter().copied().filter(|f| !f.rel.contains('/')).collect();
    // Best-ranked keyword wins; ties go to the first file.
    root.iter()
        .copied()
        .filter_map(|f| Some((rules.cover_rank(file_name(f))?, f)))
        .min_by_key(|(rank, _)| *rank)
        .map(|(_, f)| f)
        .or_else(|| root.first().copied())
        .or_else(|| {
            images.iter().copied().find(|f| {
                let name = file_name(f);
                let stem = name.rsplit_once('.').map(|s| s.0).unwrap_or(name);
                rules.cover_rank(name).is_some() || SCAN_COVER_NAME.is_match(stem)
            })
        })
        .or_else(|| images.first().copied())
}

pub fn analyze(root: &Path, dir: &Path, cache_dir: &Path) -> Album {
    let (fingerprint, files) = list_files(dir);
    analyze_files(root, dir, cache_dir, fingerprint, files)
}

pub fn analyze_files(root: &Path, dir: &Path, cache_dir: &Path, fingerprint: u64, files: Vec<FileRec>) -> Album {
    let folder_name = dir.file_name().and_then(|n| n.to_str()).unwrap_or("").to_string();
    let id = dir.strip_prefix(root).unwrap_or(dir).to_string_lossy().replace('\\', "/");

    let audio_files: Vec<&FileRec> = files.iter().filter(|f| is_audio_ext(&f.ext)).collect();
    let cue_files: Vec<&FileRec> = files.iter().filter(|f| f.ext == "cue").collect();
    let log_files: Vec<&FileRec> = files.iter().filter(|f| f.ext == "log").collect();
    let image_files: Vec<&FileRec> = files.iter().filter(|f| is_image_ext(&f.ext)).collect();
    let disc_image = files.iter().any(|f| matches!(f.ext.as_str(), "iso" | "mds" | "mdf" | "m2ts"));

    let infos = discs::probe_all(&audio_files);
    let built = discs::build(&audio_files, &infos, &cue_files);

    let logs: Vec<RipLog> = log_files
        .iter()
        .filter_map(|f| {
            let d = text::read_decoded(&f.path).ok()?;
            Some(riplog::parse(&f.path.to_string_lossy(), &d.text, &d.encoding))
        })
        // Ignore unrelated logs (e.g. tool output) that aren't rip logs.
        .filter(|l| l.ripper != "Unknown" || l.drive.is_some())
        .collect();

    // ---- metadata ----
    let (mut date, mut year, mut title) = (None, None, folder_name.clone());
    let rules = rules::current();
    let standard_name = if let Some(m) = rules.parse_name(&folder_name) {
        (date, year, title) = (m.date, m.year, m.title);
        true
    } else {
        false
    };
    if year.is_none() {
        let parent_year = dir.parent().and_then(|p| p.file_name()).and_then(|n| n.to_str()).and_then(|n| n.parse::<i32>().ok());
        let tag_year = infos.iter().filter_map(|a| a.date.as_deref()).filter_map(|d| d.get(0..4)?.parse::<i32>().ok()).next();
        let cue_year = built.cue_sheets.iter().filter_map(|c| c.date.as_deref()?.get(0..4)?.parse().ok()).next();
        year = parent_year.filter(|y| (1900..2100).contains(y)).or(tag_year).or(cue_year);
    }

    let n_audio = infos.len().max(1);
    let artist = most_common(infos.iter().filter_map(|a| a.album_artist.as_deref()))
        .map(|x| x.0)
        .or_else(|| built.cue_sheets.iter().find_map(|c| c.performer.clone()))
        .or_else(|| most_common(infos.iter().filter_map(|a| a.artist.as_deref())).filter(|(_, n)| n * 2 >= n_audio).map(|x| x.0))
        .or_else(|| {
            let performers = built.cue_sheets.iter().flat_map(|c| c.tracks.iter().filter_map(|t| t.performer.as_deref()));
            most_common(performers).map(|x| x.0)
        });
    let genre = built
        .cue_sheets
        .iter()
        .find_map(|c| c.genre.clone())
        .or_else(|| most_common(infos.iter().filter_map(|a| a.genre.as_deref())).map(|x| x.0));

    // ---- formats / quality ----
    let mut fmt_count: HashMap<String, usize> = HashMap::new();
    for a in &infos {
        *fmt_count.entry(a.format.clone()).or_default() += 1;
    }
    let mut formats: Vec<(String, usize)> = fmt_count.into_iter().collect();
    formats.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    let formats: Vec<String> = formats.into_iter().map(|f| f.0).collect();
    let sample_rate = infos.iter().map(|a| a.sample_rate).max().unwrap_or(0);
    let bit_depth = infos.iter().filter(|a| !a.is_dsd).map(|a| a.bit_depth).max().unwrap_or(0);
    let quality = if infos.is_empty() {
        AudioQuality::Unknown
    } else if infos.iter().any(|a| a.is_dsd) {
        AudioQuality::Dsd
    } else if sample_rate > 48000 || bit_depth >= 24 {
        AudioQuality::HiRes
    } else if audio_files.iter().all(|f| LOSSY_EXTS.contains(&f.ext.as_str())) {
        AudioQuality::Lossy
    } else {
        AudioQuality::Lossless
    };

    let cue_image = built.discs.iter().any(|d| d.cue_path.is_some() && d.tracks.len() > 1 && {
        let first = &d.tracks[0].file;
        d.tracks.iter().all(|t| &t.file == first)
    });
    let sacd = logs.iter().any(|l| l.ripper == "SACD-Ripper");
    let quality = if audio_files.is_empty() && sacd { AudioQuality::Dsd } else { quality };
    let source = if audio_files.is_empty() && disc_image {
        AlbumSource::DiscImage
    } else if !logs.is_empty() || cue_image {
        AlbumSource::CdRip
    } else if !audio_files.is_empty() {
        AlbumSource::Digital
    } else if disc_image {
        AlbumSource::DiscImage
    } else {
        AlbumSource::Unknown
    };
    // ---- cover ----
    let cover = pick_cover(&image_files, &rules);
    let mut cover_path = cover.map(|c| c.path.to_string_lossy().into_owned());
    let mut cover_thumb = cover.and_then(|c| imaging::thumbnail(&c.path, cache_dir, COVER_THUMB).ok());
    if cover_thumb.is_none() {
        for f in audio_files.iter().take(3) {
            if let Some(bytes) = audio::embedded_cover(&f.path) {
                if let Ok(t) = imaging::thumbnail_from_bytes(&bytes, &f.path, cache_dir, COVER_THUMB) {
                    cover_path = Some(t.to_string_lossy().into_owned());
                    cover_thumb = Some(t);
                    break;
                }
            }
        }
    }
    let accent_color = cover_thumb.as_deref().and_then(imaging::accent_color);

    // ---- issues ----
    let mut issues = Vec::new();
    if cover_thumb.is_none() {
        issues.push(Issue { kind: IssueKind::MissingCover, message: "没有找到封面图片".into(), path: None });
    }
    for c in &built.cues {
        if !c.is_utf8 {
            issues.push(Issue { kind: IssueKind::CueEncoding, message: format!("CUE 编码为 {}，建议转换为 UTF-8", c.encoding), path: Some(c.path.clone()) });
        }
        if let Some(first) = c.missing_files.first() {
            let more = if c.missing_files.len() > 1 { format!(" 等 {} 个文件", c.missing_files.len()) } else { String::new() };
            issues.push(Issue {
                kind: IssueKind::CueMissingFile,
                message: format!("CUE 引用的文件不存在：{first}{more}"),
                path: Some(c.path.clone()),
            });
        }
    }
    if !standard_name {
        issues.push(Issue { kind: IssueKind::NonStandardName, message: format!("文件夹名不符合命名格式（{}）", rules.source.name_templates.join("、")), path: None });
    }

    let mut images: Vec<ImageItem> = image_files
        .iter()
        .map(|f| ImageItem {
            path: f.path.to_string_lossy().into_owned(),
            group: f.rel.rsplit_once('/').map(|(d, _)| d.to_string()).unwrap_or_default(),
            size: f.size as i64,
        })
        .collect();
    images.sort_by(|a, b| natural_cmp(&a.group, &b.group).then_with(|| natural_cmp(&a.path, &b.path)));

    let mut summary = AlbumSummary {
        id,
        path: dir.to_string_lossy().into_owned(),
        folder_name,
        title,
        artist,
        date,
        year,
        genre,
        source,
        quality,
        quality_label: if !audio_files.is_empty() {
            quality_label(&audio_files, &infos)
        } else if sacd {
            "SACD ISO".into()
        } else if files.iter().any(|f| f.ext == "m2ts") {
            "Blu-ray / DVD".into()
        } else if disc_image {
            "光盘镜像".into()
        } else {
            String::new()
        },
        formats,
        sample_rate: sample_rate as i32,
        bit_depth: bit_depth as i32,
        disc_count: built.discs.len() as i32,
        track_count: built.discs.iter().map(|d| d.tracks.len() as i32).sum(),
        duration_secs: built.discs.iter().flat_map(|d| &d.tracks).map(|t| t.duration_secs).sum(),
        total_size: files.iter().map(|f| f.size as i64).sum(),
        audio_size: audio_files.iter().map(|f| f.size as i64).sum(),
        image_count: images.len() as i32,
        has_cue: !cue_files.is_empty(),
        has_log: !logs.is_empty(),
        // Set by apply_source below.
        rip_status: RipStatus::NotApplicable,
        cover_path,
        cover_thumb: cover_thumb.map(|p| p.to_string_lossy().into_owned()),
        accent_color,
        added_at: std::fs::metadata(dir).map(|m| unix_secs(m.created())).unwrap_or(0),
        modified_at: files.iter().map(|f| f.mtime).max().unwrap_or(0),
        issues,
        overrides: AlbumOverride::default(),
    };
    apply_source(&mut summary, &logs, source);
    Album {
        summary,
        discs: built.discs,
        logs,
        cues: built.cues,
        images,
        files: files.iter().map(|f| FileEntry { rel_path: f.rel.clone(), size: f.size as i64 }).collect(),
        fingerprint,
    }
}

/// Sets the album source and everything derived from it: the rip status and
/// the rip-related issues (which only apply to CD rips).
pub fn apply_source(summary: &mut AlbumSummary, logs: &[RipLog], source: AlbumSource) {
    summary.source = source;
    summary.rip_status = if source != AlbumSource::CdRip {
        RipStatus::NotApplicable
    } else if logs.is_empty() {
        RipStatus::NoLog
    } else {
        logs.iter().map(|l| l.status).max_by_key(|s| severity(*s)).unwrap_or(RipStatus::Unknown)
    };
    summary.issues.retain(|i| !matches!(i.kind, IssueKind::RipErrors | IssueKind::RipUnverified | IssueKind::MissingLog));
    if source != AlbumSource::CdRip {
        return;
    }
    for l in logs {
        match l.status {
            RipStatus::Error => summary.issues.push(Issue { kind: IssueKind::RipErrors, message: "抓轨日志报告了读取错误或 CRC 不一致".into(), path: Some(l.path.clone()) }),
            RipStatus::Warning => summary.issues.push(Issue { kind: IssueKind::RipUnverified, message: "部分音轨未通过 AccurateRip 校验".into(), path: Some(l.path.clone()) }),
            _ => {}
        }
    }
    if summary.rip_status == RipStatus::NoLog {
        summary.issues.push(Issue { kind: IssueKind::MissingLog, message: "CD 镜像缺少抓轨日志".into(), path: None });
    }
}

/// Uses `image` as the album cover (thumbnail, accent color). Returns false
/// and leaves the summary untouched if the image can't be read.
pub fn apply_cover(summary: &mut AlbumSummary, image: &Path, cache_dir: &Path) -> bool {
    let Ok(thumb) = imaging::thumbnail(image, cache_dir, COVER_THUMB) else { return false };
    summary.cover_path = Some(image.to_string_lossy().into_owned());
    summary.accent_color = imaging::accent_color(&thumb);
    summary.cover_thumb = Some(thumb.to_string_lossy().into_owned());
    summary.issues.retain(|i| i.kind != IssueKind::MissingCover);
    true
}
