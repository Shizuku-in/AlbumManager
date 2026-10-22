//! Bangumi (https://bangumi.github.io/api/): anime / game soundtracks and
//! doujin music, with catalog numbers and event names in the infobox.

use crate::musicbrainz::text;
use crate::AGENT;
use album_model::{MatchKind, OnlineMatch, OnlineSource};
use anyhow::Result;
use regex::Regex;
use serde_json::{json, Value};
use std::sync::LazyLock;

const SOURCE: &str = "Bangumi";
/// Subject type "music".
const MUSIC: i32 = 3;

/// "(C95)" / "(M3-55)" after a release date.
static EVENT: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)[(（]\s*(C\d{2,3}|M3[-‐ ]?\d+[^)）]*|COMITIA\s?\d+|[^)）]*(?:例大祭|紅楼夢|コミケ|コミックマーケット|ボーマス|ボカコレ|サンシャインクリエイション)[^)）]*)\s*[)）]",
    )
    .unwrap()
});

/// An infobox value: a string, or a list of `{k?, v}` (joined with "、").
fn info(subject: &Value, keys: &[&str]) -> Option<String> {
    let item = subject["infobox"]
        .as_array()?
        .iter()
        .find(|i| keys.contains(&i["key"].as_str().unwrap_or("")))?;
    match &item["value"] {
        Value::Array(list) => {
            let parts: Vec<String> = list.iter().filter_map(|e| text(&e["v"])).collect();
            Some(parts.join("、")).filter(|s| !s.is_empty())
        }
        v => text(v),
    }
}

/// The first catalog number of e.g. "KSLA-0149～151（PC流通版） / KSLM-...".
fn first_catalog(s: &str) -> Option<String> {
    let first = s.split(" / ").next()?;
    let first = first.split(['（', '(']).next()?.trim();
    Some(first.to_string()).filter(|s| !s.is_empty())
}

fn subject(v: &Value) -> Option<OnlineMatch> {
    let id = v["id"].as_i64()?;
    let images = &v["images"];
    Some(OnlineMatch {
        via: OnlineSource::Bangumi,
        source: SOURCE.into(),
        id: id.to_string(),
        url: format!("https://bgm.tv/subject/{id}"),
        title: text(&v["name"]).or_else(|| text(&v["name_cn"]))?,
        artist: info(v, &["艺术家", "社团"]),
        date: text(&v["date"]),
        catalog: info(v, &["商品编号", "品番"]).and_then(|c| first_catalog(&c)),
        event: info(v, &["发售日期"]).and_then(|d| Some(EVENT.captures(&d)?[1].trim().to_string())),
        label: info(v, &["厂牌"]),
        country: None,
        format: info(v, &["版本特性"]),
        disc_count: info(v, &["碟片数量"])
            .and_then(|n| n.parse().ok())
            .unwrap_or(0),
        track_count: 0,
        thumb_url: text(&images["medium"]).or_else(|| text(&images["common"])),
        cover_url: text(&images["large"]),
        matched_by: MatchKind::Title,
        score: 0,
    })
}

/// Music subjects whose name matches `keyword`, in Bangumi's order.
pub fn search(keyword: &str) -> Result<Vec<OnlineMatch>> {
    let v: Value = AGENT
        .post("https://api.bgm.tv/v0/search/subjects")
        .query("limit", "10")
        .send_json(json!({ "keyword": keyword, "filter": { "type": [MUSIC] } }))?
        .into_json()?;
    let found = v["data"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(subject);
    // No relevance score: rank by position.
    Ok(found
        .enumerate()
        .map(|(i, m)| OnlineMatch {
            score: 90 - 5 * i as i32,
            ..m
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn event_after_date() {
        let ev = |s: &str| EVENT.captures(s).map(|c| c[1].to_string());
        assert_eq!(ev("2018-12-29 (C95) (CD)").as_deref(), Some("C95"));
        assert_eq!(ev("2025-04-27 (M3-55)").as_deref(), Some("M3-55"));
        assert_eq!(ev("2019-07-27"), None);
    }

    #[test]
    fn catalog_of_list() {
        assert_eq!(
            first_catalog("KSLA-0149～151（PC流通版） / KSLM-0149～151（音楽流通版）").as_deref(),
            Some("KSLA-0149～151")
        );
    }
}
