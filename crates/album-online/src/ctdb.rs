//! CueTools database (http://db.cuetools.net): metadata from MusicBrainz,
//! Discogs and FreeDB by a disc's table of contents, in one request.

use crate::discid::Toc;
use crate::AGENT;
use album_model::{MatchKind, OnlineMatch, OnlineSource};
use anyhow::Result;
use regex::Regex;
use std::collections::HashMap;
use std::sync::LazyLock;

static METADATA: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?s)<metadata\s([^>]*)>(.*?)</metadata>").unwrap());
static TAG: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"<(\w+)\s([^>]*?)/?>").unwrap());
static ATTR: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"([\w:]+)="([^"]*)""#).unwrap());

fn unescape(s: &str) -> String {
    s.replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
}

fn attrs(s: &str) -> HashMap<String, String> {
    ATTR.captures_iter(s)
        .map(|c| (c[1].to_string(), unescape(&c[2])))
        .filter(|(_, v)| !v.trim().is_empty())
        .collect()
}

fn entry(head: &str, body: &str) -> Option<OnlineMatch> {
    let a = attrs(head);
    let id = a.get("id")?.clone();
    let (source, url) = match a.get("source").map(String::as_str) {
        Some("musicbrainz") => (
            "MusicBrainz",
            format!("https://musicbrainz.org/release/{id}"),
        ),
        Some("discogs") => ("Discogs", format!("https://www.discogs.com/release/{id}")),
        Some("freedb") => ("FreeDB", String::new()),
        _ => ("CTDB", String::new()),
    };
    let relevance = a
        .get("relevance")
        .and_then(|r| r.parse().ok())
        .unwrap_or(100);
    let mut tracks = 0;
    let (mut catalog, mut label, mut date, mut country) = (None, None, None, None);
    let (mut thumb, mut cover) = (None, None);
    for t in TAG.captures_iter(body) {
        let mut ta = attrs(&t[2]);
        match &t[1] {
            "track" => tracks += 1,
            "label" if catalog.is_none() => {
                catalog = ta.remove("catno");
                label = ta.remove("name");
            }
            "release" if date.is_none() => {
                date = ta.remove("date");
                country = ta.remove("country");
            }
            // The first primary picture is the front cover.
            "coverart" if cover.is_none() && ta.get("primary").map(String::as_str) == Some("1") => {
                thumb = ta.remove("uri150");
                cover = ta.remove("uri");
            }
            _ => {}
        }
    }
    Some(OnlineMatch {
        via: OnlineSource::Ctdb,
        source: source.into(),
        url,
        title: a.get("album")?.clone(),
        artist: a.get("artist").cloned(),
        date: date.or_else(|| a.get("year").cloned()),
        catalog,
        event: None,
        label,
        country,
        format: None,
        disc_count: a.get("disccount").and_then(|n| n.parse().ok()).unwrap_or(0),
        track_count: tracks,
        thumb_url: thumb,
        cover_url: cover,
        // Entries attached to this very disc have no relevance (or a full one).
        matched_by: if relevance < 100 {
            MatchKind::Toc
        } else {
            MatchKind::DiscId
        },
        score: relevance,
        id,
    })
}

pub fn by_toc(toc: &Toc) -> Result<Vec<OnlineMatch>> {
    let xml = AGENT
        .get("http://db.cuetools.net/lookup2.php")
        .query("version", "3")
        .query("ctdb", "0")
        .query("metadata", "extensive")
        .query("fuzzy", "1")
        .query("toc", &toc.ctdb_param())
        .call()?
        .into_string()?;
    Ok(METADATA
        .captures_iter(&xml)
        .filter_map(|c| entry(&c[1], &c[2]))
        .collect())
}
