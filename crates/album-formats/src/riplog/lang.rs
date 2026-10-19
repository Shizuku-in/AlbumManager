//! English translation of logs written in any of EAC's non-English UI languages, so
//! the checker only needs to understand English. Phrases: `eac_lang.tsv`.

use regex::{Captures, Regex};
use std::collections::HashMap;
use std::sync::LazyLock;

struct Language {
    name: &'static str,
    /// Text of the log's header line in this language.
    keys: Vec<&'static str>,
    english: HashMap<&'static str, &'static str>,
    /// All phrases, longest first so the longest match wins.
    pattern: Regex,
}

static LANGUAGES: LazyLock<Vec<Language>> = LazyLock::new(|| {
    let mut langs = Vec::new();
    let mut header: Option<Vec<&'static str>> = None;
    let mut pairs: Vec<(&'static str, &'static str)> = Vec::new();
    let mut finish = |header: Option<Vec<&'static str>>, pairs: &mut Vec<_>| {
        if let Some(h) = header {
            langs.push(language(h, std::mem::take(pairs)));
        }
    };
    let tables = [
        include_str!("eac_lang.tsv"),
        include_str!("eac_lang_extra.tsv"),
    ];
    for line in tables.iter().flat_map(|t| t.lines()) {
        if line.starts_with('#') || line.is_empty() {
            continue;
        }
        if let Some(h) = line.strip_prefix('@') {
            finish(header.take(), &mut pairs);
            header = Some(h.split('\t').collect());
        } else if let Some((phrase, en)) = line.split_once('\t') {
            pairs.push((phrase, en));
        }
    }
    finish(header, &mut pairs);
    langs
});

fn language(header: Vec<&'static str>, mut pairs: Vec<(&'static str, &'static str)>) -> Language {
    pairs.sort_by_key(|(p, _)| std::cmp::Reverse(p.len()));
    let alternatives: Vec<String> = pairs.iter().map(|(p, _)| regex::escape(p)).collect();
    Language {
        name: header[0],
        keys: header[1..].to_vec(),
        english: pairs.into_iter().collect(),
        pattern: Regex::new(&alternatives.join("|")).unwrap(),
    }
}

/// The log in English, with the language it was translated from. None when
/// it is English already or in a language without a phrase table.
pub fn translate(text: &str) -> Option<(&'static str, String)> {
    let head = head(text);
    // Several tables can share a header (two Simplified Chinese variants):
    // keep the one that recognises the most phrases.
    let mut best: Option<(usize, &'static str, String)> = None;
    for lang in LANGUAGES
        .iter()
        .filter(|l| l.keys.iter().any(|k| head.contains(k)))
    {
        let mut count = 0;
        let translated = lang.pattern.replace_all(text, |c: &Captures| {
            count += 1;
            lang.english[&c[0]]
        });
        if count > best.as_ref().map_or(0, |b| b.0) {
            best = Some((count, lang.name, translated.into_owned()));
        }
    }
    best.map(|(_, name, text)| (name, text))
}

fn head(text: &str) -> String {
    text.lines().take(5).collect::<Vec<_>>().join("\n")
}

/// Whether the header of an EAC log reads as English or a known UI language,
/// i.e. the text was decoded with the right encoding.
pub fn header_recognised(text: &str) -> bool {
    let head = head(text);
    head.contains("EAC extraction logfile")
        || LANGUAGES
            .iter()
            .any(|l| l.keys.iter().any(|k| head.contains(k)))
}
