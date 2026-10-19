//! Types that only exist at the Dart boundary.

pub use album_model::*;

pub enum ScanEvent {
    Started {
        total: i32,
    },
    Progress {
        done: i32,
        total: i32,
        current: String,
    },
    Finished {
        albums: Vec<AlbumSummary>,
        elapsed_ms: i64,
        rescanned: i32,
    },
}

pub struct LibraryInfo {
    pub root: Option<String>,
    pub albums: Vec<AlbumSummary>,
}

pub struct CacheInfo {
    /// App data folder (config, album cache, thumbnails).
    pub data_dir: String,
    pub thumb_count: i32,
    pub thumb_bytes: i64,
}
