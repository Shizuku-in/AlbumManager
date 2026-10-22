//! MusicBrainz web service (https://musicbrainz.org/doc/MusicBrainz_API).

use crate::discid::Toc;
use crate::AGENT;
use album_model::{MatchKind, OnlineMatch, OnlineSource};
use anyhow::Result;
use serde_json::Value;
use std::sync::Mutex;
use std::time::{Duration, Instant};

const API: &str = "https://musicbrainz.org/ws/2";
const SOURCE: &str = "MusicBrainz";

/// Time of the last request: MusicBrainz allows one per second.
static LAST: Mutex<Option<Instant>> = Mutex::new(None);

/// GET `path` with `query`; `None` when MusicBrainz has no such entity.
fn get(path: &str, query: &[(&str, &str)]) -> Result<Option<Value>> {
    {
        let mut last = LAST.lock().unwrap();
        if let Some(t) = *last {
            std::thread::sleep(Duration::from_millis(1100).saturating_sub(t.elapsed()));
        }
        *last = Some(Instant::now());
    }
    let mut req = AGENT.get(&format!("{API}/{path}")).query("fmt", "json");
    for (k, v) in query {
        req = req.query(k, v);
    }
    match req.call() {
        Ok(res) => Ok(Some(res.into_json()?)),
        Err(ureq::Error::Status(404, _)) => Ok(None),
        Err(e) => Err(e.into()),
    }
}

/// `"text"` for a Lucene query.
fn quoted(text: &str) -> String {
    format!("\"{}\"", text.replace('\\', "\\\\").replace('"', "\\\""))
}

pub(crate) fn text(v: &Value) -> Option<String> {
    v.as_str()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

fn release(v: &Value, matched_by: MatchKind) -> Option<OnlineMatch> {
    let id = v["id"].as_str()?.to_string();
    let artist: String = v["artist-credit"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|c| {
            format!(
                "{}{}",
                c["name"].as_str().unwrap_or(""),
                c["joinphrase"].as_str().unwrap_or("")
            )
        })
        .collect();
    let labels = v["label-info"].as_array().into_iter().flatten();
    let media = v["media"].as_array();
    let track_count = v["track-count"].as_i64().unwrap_or_else(|| {
        media
            .into_iter()
            .flatten()
            .map(|m| m["track-count"].as_i64().unwrap_or(0))
            .sum()
    });
    let cover = |size: &str| format!("https://coverartarchive.org/release/{id}/front-{size}");
    // Lookups say whether there's artwork; search results don't.
    let has_cover = v["cover-art-archive"]["front"].as_bool().unwrap_or(true);
    Some(OnlineMatch {
        via: OnlineSource::MusicBrainz,
        source: SOURCE.into(),
        url: format!("https://musicbrainz.org/release/{id}"),
        title: text(&v["title"])?,
        artist: Some(artist.trim().to_string()).filter(|a| !a.is_empty()),
        date: text(&v["date"]),
        catalog: labels.clone().find_map(|l| text(&l["catalog-number"])),
        event: None,
        label: labels.clone().find_map(|l| text(&l["label"]["name"])),
        country: text(&v["country"]),
        format: media
            .and_then(|m| m.first())
            .and_then(|m| text(&m["format"])),
        disc_count: media.map_or(0, |m| m.len() as i32),
        track_count: track_count as i32,
        thumb_url: has_cover.then(|| cover("250")),
        cover_url: has_cover.then(|| cover("1200")),
        matched_by,
        score: v["score"].as_i64().unwrap_or(100) as i32,
        id,
    })
}

fn releases(v: Option<Value>, matched_by: MatchKind) -> Vec<OnlineMatch> {
    v.as_ref()
        .and_then(|v| v["releases"].as_array())
        .into_iter()
        .flatten()
        .filter_map(|r| release(r, matched_by))
        .collect()
}

/// Releases with this disc, or failing that (fuzzy) with a similar layout.
pub fn by_toc(toc: &Toc) -> Result<Vec<OnlineMatch>> {
    let id = toc.disc_id();
    let v = get(
        &format!("discid/{id}"),
        &[
            ("toc", &toc.param()),
            ("inc", "artist-credits+labels"),
            ("cdstubs", "no"),
        ],
    )?;
    // A disc response carries its own id; a fuzzy one is a bare release list.
    let exact = v.as_ref().is_some_and(|v| v["id"].as_str() == Some(&id));
    let kind = if exact {
        MatchKind::DiscId
    } else {
        MatchKind::Toc
    };
    Ok(releases(v, kind))
}

pub fn by_catalog(catalog: &str) -> Result<Vec<OnlineMatch>> {
    let q = format!("catno:{}", quoted(catalog));
    let v = get("release", &[("query", &q), ("limit", "10")])?;
    Ok(releases(v, MatchKind::Catalog))
}

pub fn by_title(title: &str, artist: Option<&str>) -> Result<Vec<OnlineMatch>> {
    let mut q = format!("release:{}", quoted(title));
    if let Some(a) = artist {
        q += &format!(" AND artist:{}", quoted(a));
    }
    let v = get("release", &[("query", &q), ("limit", "10")])?;
    Ok(releases(v, MatchKind::Title))
}
