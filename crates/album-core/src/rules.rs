//! User-editable recognition rules: cover file names and album folder name
//! templates. Compiled once and shared by scans.

use album_model::ScanRules;
use anyhow::{anyhow, Result};
use regex::Regex;
use std::sync::{Arc, LazyLock, RwLock};

pub fn defaults() -> ScanRules {
    ScanRules {
        cover_keywords: ["cover", "folder", "front", "jacket", "album", "ジャケット", "封面"].map(String::from).to_vec(),
        name_templates: vec!["[{date}] {title}".into()],
    }
}

pub struct Rules {
    pub source: ScanRules,
    /// Lowercased cover keywords, in priority order.
    cover: Vec<String>,
    names: Vec<Regex>,
}

/// Date and title read from a folder name.
pub struct NameMatch {
    pub date: Option<String>,
    pub year: Option<i32>,
    pub title: String,
}

const DATE_RE: &str = r"\d{8}|\d{6}|\d{4}[-./]\d{1,2}(?:[-./]\d{1,2})?";
const YEAR_RE: &str = r"(?:19|20)\d{2}";

/// Turns a template like `[{date}] {title}` into an anchored regex. Runs of
/// whitespace match any amount of whitespace.
fn compile_template(t: &str) -> Result<Regex> {
    let t = t.trim();
    let count = |tok: &str| t.matches(tok).count();
    if count("{title}") != 1 {
        return Err(anyhow!("“{t}” 需要包含一个 {{title}}"));
    }
    if count("{date}") + count("{year}") != 1 {
        return Err(anyhow!("“{t}” 需要包含一个 {{date}} 或 {{year}}"));
    }
    let mut re = String::from("^");
    let mut rest = t;
    while !rest.is_empty() {
        if let Some(r) = rest.strip_prefix("{date}") {
            re += &format!("(?P<date>{DATE_RE})");
            rest = r;
        } else if let Some(r) = rest.strip_prefix("{year}") {
            re += &format!("(?P<year>{YEAR_RE})");
            rest = r;
        } else if let Some(r) = rest.strip_prefix("{title}") {
            re += "(?P<title>.+)";
            rest = r;
        } else {
            let c = rest.chars().next().unwrap();
            if c.is_whitespace() {
                re += r"\s*";
                rest = rest.trim_start();
            } else {
                re += &regex::escape(&c.to_string());
                rest = &rest[c.len_utf8()..];
            }
        }
    }
    re += "$";
    Ok(Regex::new(&re)?)
}

/// `YYMMDD`, `YYYYMMDD` or `YYYY-MM[-DD]` (any of `-./`) → (ISO date, year).
pub fn parse_date(code: &str) -> (Option<String>, Option<i32>) {
    let parts: Vec<&str> = code.split(['-', '.', '/']).collect();
    let (y, m, d) = if parts.len() > 1 {
        let n = |i: usize| parts.get(i).and_then(|p| p.parse::<u32>().ok()).unwrap_or(0);
        (parts[0].parse::<i32>().ok(), n(1), n(2))
    } else {
        let (y, rest) = if code.len() == 8 {
            (code[0..4].parse::<i32>().ok(), &code[4..])
        } else {
            let yy: i32 = code[0..2].parse().unwrap_or(0);
            (Some(if yy <= 50 { 2000 + yy } else { 1900 + yy }), &code[2..])
        };
        (y, rest[0..2].parse().unwrap_or(0), rest[2..4].parse().unwrap_or(0))
    };
    let Some(y) = y else { return (None, None) };
    let s = match (m, d) {
        (1..=12, 1..=31) => format!("{y:04}-{m:02}-{d:02}"),
        (1..=12, _) => format!("{y:04}-{m:02}"),
        _ => format!("{y:04}"),
    };
    (Some(s), Some(y))
}

impl Rules {
    pub fn compile(source: ScanRules) -> Result<Self> {
        let names = source.name_templates.iter().filter(|t| !t.trim().is_empty()).map(|t| compile_template(t)).collect::<Result<_>>()?;
        let cover = source.cover_keywords.iter().map(|k| k.trim().to_lowercase()).filter(|k| !k.is_empty()).collect();
        Ok(Self { source, cover, names })
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
            Some(NameMatch { date, year, title })
        })
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
pub fn set(rules: ScanRules) -> Result<()> {
    *CURRENT.write().unwrap() = Arc::new(Rules::compile(rules)?);
    Ok(())
}

