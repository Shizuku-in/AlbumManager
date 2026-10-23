//! User-editable recognition rules: cover file names and album folder name
//! templates. Compiled once and shared by scans.

use album_model::{RipRules, ScanRules};
use anyhow::{anyhow, Result};
use regex::Regex;
use std::sync::{Arc, LazyLock, RwLock};

pub fn defaults() -> ScanRules {
    ScanRules::default()
}

pub struct Rules {
    pub source: ScanRules,
    /// Lowercased cover keywords, in priority order.
    cover: Vec<String>,
    /// Lowercased scan folder keywords.
    scan_folders: Vec<String>,
    names: Vec<Regex>,
    /// All ignore patterns as one case-insensitive regex.
    ignore: Option<Regex>,
}

/// Values read from a folder name.
pub struct NameMatch {
    pub date: Option<String>,
    pub year: Option<i32>,
    pub title: String,
    pub catalog: Option<String>,
    pub artist: Option<String>,
    pub event: Option<String>,
}

/// Template placeholders and their regexes. `{date}` takes 240315,
/// 20240315 or 2024-03[-15] (any of `-./`); `{catalog}` takes catalog
/// numbers such as LACA-15800, SVWC70501~2 or KICA-1234～5; `{*}` matches
/// text that is skipped (e.g. `[FLAC]`). Free text other than the title
/// matches as little as it can, so the title gets the rest.
const PLACEHOLDERS: [(&str, &str); 7] = [
    (
        "{date}",
        r"(?P<date>\d{8}|\d{6}|\d{4}[-./]\d{1,2}(?:[-./]\d{1,2})?)",
    ),
    ("{year}", r"(?P<year>(?:19|20)\d{2})"),
    (
        "{catalog}",
        r"(?P<catalog>[A-Za-z]{2,6}-?\d{2,6}(?:[~～]\d{1,6})?)",
    ),
    ("{artist}", "(?P<artist>.+?)"),
    ("{event}", "(?P<event>.+?)"),
    ("{title}", "(?P<title>.+)"),
    ("{*}", ".*?"),
];

/// Turns a template like `[{date}] {title}` into an anchored regex. Runs of
/// whitespace match any amount of whitespace.
fn compile_template(t: &str) -> Result<Regex> {
    let t = t.trim();
    let count = |tok: &str| t.matches(tok).count();
    if count("{title}") != 1 {
        return Err(anyhow!("“{t}” 需要包含一个 {{title}}"));
    }
    for tok in ["{date}", "{year}", "{catalog}", "{artist}", "{event}"] {
        if count(tok) > 1 {
            return Err(anyhow!("“{t}” 中 {tok} 只能出现一次"));
        }
    }
    if count("{date}") + count("{year}") > 1 {
        return Err(anyhow!("“{t}” 不能同时包含 {{date}} 和 {{year}}"));
    }
    // A bare `{title}` would make every folder an album.
    if ["{date}", "{year}", "{catalog}", "{artist}", "{event}"]
        .iter()
        .all(|tok| count(tok) == 0)
    {
        return Err(anyhow!(
            "“{t}” 除 {{title}} 外还需要 {{date}}、{{year}}、{{catalog}}、{{artist}} 或 {{event}} 之一"
        ));
    }
    let mut re = String::from("^");
    let mut rest = t;
    'outer: while !rest.is_empty() {
        for (tok, pat) in PLACEHOLDERS {
            if let Some(r) = rest.strip_prefix(tok) {
                re += pat;
                rest = r;
                continue 'outer;
            }
        }
        let c = rest.chars().next().unwrap();
        if c.is_whitespace() {
            re += r"\s*";
            rest = rest.trim_start();
        } else {
            re += &regex::escape(&c.to_string());
            rest = &rest[c.len_utf8()..];
        }
    }
    re += "$";
    Ok(Regex::new(&re)?)
}

/// `YYMMDD`, `YYYYMMDD` or `YYYY-MM[-DD]` (any of `-./`) → (ISO date, year).
pub fn parse_date(code: &str) -> (Option<String>, Option<i32>) {
    let parts: Vec<&str> = code.split(['-', '.', '/']).collect();
    let (y, m, d) = if parts.len() > 1 {
        let n = |i: usize| {
            parts
                .get(i)
                .and_then(|p| p.parse::<u32>().ok())
                .unwrap_or(0)
        };
        (parts[0].parse::<i32>().ok(), n(1), n(2))
    } else {
        let (y, rest) = if code.len() == 8 {
            (code[0..4].parse::<i32>().ok(), &code[4..])
        } else {
            let yy: i32 = code[0..2].parse().unwrap_or(0);
            (
                Some(if yy <= 50 { 2000 + yy } else { 1900 + yy }),
                &code[2..],
            )
        };
        (
            y,
            rest[0..2].parse().unwrap_or(0),
            rest[2..4].parse().unwrap_or(0),
        )
    };
    let Some(y) = y else { return (None, None) };
    let s = match (m, d) {
        (1..=12, 1..=31) => format!("{y:04}-{m:02}-{d:02}"),
        (1..=12, _) => format!("{y:04}-{m:02}"),
        _ => format!("{y:04}"),
    };
    (Some(s), Some(y))
}

/// `*` = any run of characters, `?` = one character, the rest literal.
fn glob_to_regex(glob: &str) -> String {
    glob.chars()
        .map(|c| match c {
            '*' => ".*".to_string(),
            '?' => ".".to_string(),
            c => regex::escape(&c.to_string()),
        })
        .collect()
}

/// A date typed by hand: `2024`, or anything `{date}` accepts. Returns
/// (ISO date, year), or None when it isn't one.
pub fn parse_typed_date(s: &str) -> Option<(String, i32)> {
    static DATE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"^(?:\d{8}|\d{6}|\d{4}[-./]\d{1,2}(?:[-./]\d{1,2})?)$").unwrap()
    });
    let s = s.trim();
    if s.len() == 4 && s.bytes().all(|b| b.is_ascii_digit()) {
        return Some((s.to_string(), s.parse().ok()?));
    }
    if !DATE.is_match(s) {
        return None;
    }
    match parse_date(s) {
        (Some(d), Some(y)) => Some((d, y)),
        _ => None,
    }
}

impl Rules {
    pub fn compile(source: ScanRules) -> Result<Self> {
        let names = source
            .name_templates
            .iter()
            .filter(|t| !t.trim().is_empty())
            .map(|t| compile_template(t))
            .collect::<Result<_>>()?;
        let lower = |list: &[String]| {
            list.iter()
                .map(|k| k.trim().to_lowercase())
                .filter(|k| !k.is_empty())
                .collect()
        };
        let cover = lower(&source.cover_keywords);
        let scan_folders = lower(&source.scan_folder_keywords);
        let globs: Vec<String> = source
            .ignore_folders
            .iter()
            .map(|g| g.trim())
            .filter(|g| !g.is_empty())
            .map(glob_to_regex)
            .collect();
        let ignore = (!globs.is_empty())
            .then(|| Regex::new(&format!("(?i)^(?:{})$", globs.join("|"))))
            .transpose()?;
        Ok(Self {
            source,
            cover,
            scan_folders,
            names,
            ignore,
        })
    }

    /// Priority of an image file name as a cover (lower is better).
    pub fn cover_rank(&self, file_name: &str) -> Option<usize> {
        let name = file_name.to_lowercase();
        self.cover.iter().position(|k| name.starts_with(k.as_str()))
    }

    pub fn parse_name(&self, name: &str) -> Option<NameMatch> {
        self.names.iter().find_map(|re| {
            let c = re.captures(name)?;
            let title = c["title"].trim().to_string();
            let (date, year) = match (c.name("date"), c.name("year")) {
                (Some(d), _) => parse_date(d.as_str()),
                (_, Some(y)) => (Some(y.as_str().to_string()), y.as_str().parse().ok()),
                _ => (None, None),
            };
            let text = |name| {
                c.name(name)
                    .map(|m| m.as_str().trim().to_string())
                    .filter(|s| !s.is_empty())
            };
            Some(NameMatch {
                date,
                year,
                title,
                catalog: text("catalog").map(|s| s.to_uppercase()),
                artist: text("artist"),
                event: text("event"),
            })
        })
    }

    /// Whether an album's images (paths relative to the album folder, `/`
    /// separated) include scans.
    pub fn has_scans<'a>(&self, image_rels: impl ExactSizeIterator<Item = &'a str>) -> bool {
        let n = self.source.scan_min_images as usize;
        if n > 0 && image_rels.len() >= n {
            return true;
        }
        image_rels
            .filter_map(|rel| rel.rsplit_once('/'))
            .any(|(dir, _)| {
                let dir = dir.to_lowercase();
                self.scan_folders.iter().any(|k| dir.contains(k.as_str()))
            })
    }

    /// Whether scans skip a folder with this name: hidden (`.` / `$`
    /// prefix) or matching an ignore pattern.
    pub fn ignores_dir(&self, name: &str) -> bool {
        name.starts_with('.')
            || name.starts_with('$')
            || self.ignore.as_ref().is_some_and(|re| re.is_match(name))
    }

    pub fn is_album_name(&self, name: &str) -> bool {
        self.names.iter().any(|re| re.is_match(name))
    }
}

static CURRENT: LazyLock<RwLock<Arc<Rules>>> =
    LazyLock::new(|| RwLock::new(Arc::new(Rules::compile(defaults()).unwrap())));

pub fn current() -> Arc<Rules> {
    CURRENT.read().unwrap().clone()
}

/// Validates and installs new rules.
pub(crate) fn set(rules: ScanRules) -> Result<()> {
    *CURRENT.write().unwrap() = Arc::new(Rules::compile(rules)?);
    Ok(())
}

/// How rip logs are judged (see [RipRules]).
static RIP: LazyLock<RwLock<RipRules>> =
    LazyLock::new(|| RwLock::new(album_formats::riplog::default_rules()));

pub fn rip() -> RipRules {
    RIP.read().unwrap().clone()
}

pub(crate) fn set_rip(rules: RipRules) {
    *RIP.write().unwrap() = rules;
}
