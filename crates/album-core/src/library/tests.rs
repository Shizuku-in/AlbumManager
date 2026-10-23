//! Diagnostics against a real library:
//! `$env:ALBUM_ROOT="F:/Music"; cargo test --release --lib real_library -- --ignored --nocapture`

use super::*;
use album_model::*;
use std::collections::HashMap;
use std::path::Path;

#[test]
fn scan_rejects_conflicting_writes_and_releases_gate() {
    let data = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../target")
        .join(format!(
            "album-scan-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
    let root = data.join("library");
    let other = data.join("other");
    std::fs::create_dir_all(&root).unwrap();
    std::fs::create_dir(&other).unwrap();
    init(&data).unwrap();
    set_root(&root).unwrap();
    scan(false, |_, _, _| {
        assert!(set_root(&other).is_err());
        assert!(set_override("album", AlbumOverride::default()).is_err());
        assert!(set_rules(ScanRules::default()).is_err());
        assert!(set_rip_rules(album_formats::riplog::default_rules()).is_err());
        assert!(rescan_album("album").is_err());
    })
    .unwrap();
    assert_eq!(dirs().unwrap().0, root);
    set_root(&other).unwrap();
    assert_eq!(dirs().unwrap().0, other);
    std::fs::remove_dir_all(data).unwrap();
}

#[test]
#[ignore]
fn real_library() {
    let root = std::env::var("ALBUM_ROOT").unwrap_or_else(|_| "F:/Music".into());
    let data = std::env::temp_dir().join("album_manager_test");
    init(&data).unwrap();
    set_root(Path::new(&root)).unwrap();
    let t = std::time::Instant::now();
    let n = scan(true, |_, _, _| {}).unwrap();
    let st = STATE.read().unwrap();
    println!(
        "albums={} rescanned={n} in {:?}",
        st.albums.len(),
        t.elapsed()
    );
    let count = |label: &str, f: &dyn Fn(&Album) -> String| {
        let mut m: HashMap<String, usize> = HashMap::new();
        for a in &st.albums {
            *m.entry(f(a)).or_default() += 1;
        }
        let mut v: Vec<_> = m.into_iter().collect();
        v.sort_by(|a, b| b.1.cmp(&a.1));
        println!("{label}: {:?}", v.iter().take(12).collect::<Vec<_>>());
    };
    count("source", &|a| format!("{:?}", a.summary.source));
    count("quality", &|a| format!("{:?}", a.summary.quality));
    count("rip", &|a| format!("{:?}", a.summary.rip_status));
    count("label", &|a| a.summary.quality_label.clone());
    count("cover", &|a| a.summary.cover_thumb.is_some().to_string());
    let mut issues: HashMap<String, usize> = HashMap::new();
    for a in &st.albums {
        for i in &a.summary.issues {
            *issues.entry(format!("{:?}", i.kind)).or_default() += 1;
        }
    }
    println!("issues: {issues:?}");
    for (a, i) in st
        .albums
        .iter()
        .flat_map(|a| a.summary.issues.iter().map(move |i| (a, i)))
        .filter(|(_, i)| i.kind == IssueKind::CueMissingFile)
        .take(40)
    {
        println!("MISSING: {} :: {}", a.summary.id, i.message);
    }
    for a in st
        .albums
        .iter()
        .filter(|a| a.summary.track_count == 0)
        .take(10)
    {
        println!("NO TRACKS: {}", a.summary.id);
    }
    for a in st
        .albums
        .iter()
        .filter(|a| {
            a.summary.rip_status == RipStatus::Unknown || a.summary.rip_status == RipStatus::Error
        })
        .take(10)
    {
        println!("RIP {:?}: {}", a.summary.rip_status, a.summary.id);
    }
    for a in st.albums.iter().step_by(97).take(8) {
        let s = &a.summary;
        println!(
            "- {} | {:?} | {:?} | {} | discs={} tracks={} {:.0}min | accent={:?}",
            s.title,
            s.artist,
            s.date,
            s.quality_label,
            s.disc_count,
            s.track_count,
            s.duration_secs / 60.0,
            s.accent_color.map(|c| format!("{c:08X}"))
        );
    }
}
