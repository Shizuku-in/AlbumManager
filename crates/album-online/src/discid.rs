//! MusicBrainz disc IDs, computed from a CD's table of contents.

use sha1::{Digest, Sha1};

/// Lead-in before track 1, in sectors.
const LEAD_IN: u32 = 150;
/// Gap before the data session of an enhanced CD, in sectors.
const SESSION_GAP: u32 = 11400;

/// Table of contents of the audio session of a CD: absolute sector offsets
/// (lead-in included) of each track and of the lead-out.
#[derive(Debug, Clone, PartialEq)]
pub struct Toc {
    pub offsets: Vec<u32>,
    pub lead_out: u32,
}

impl Toc {
    /// From the "TOC of the extracted CD" table of an EAC / XLD log (rows of
    /// `track | start | length | start sector | end sector`, headers may be
    /// translated).
    pub fn from_log(text: &str) -> Option<Toc> {
        let mut rows: Vec<(u32, u32)> = Vec::new();
        for line in text.lines() {
            let cols: Vec<&str> = line.split('|').map(str::trim).collect();
            let row = (cols.len() == 5)
                .then(|| {
                    Some((
                        cols[0].parse::<usize>().ok()?,
                        cols[3].parse::<u32>().ok()?,
                        cols[4].parse::<u32>().ok()?,
                    ))
                })
                .flatten();
            match row {
                Some((n, start, end)) if n == rows.len() + 1 => rows.push((start, end)),
                _ if !rows.is_empty() => break,
                _ => {}
            }
        }
        // Enhanced CD: the data track follows the audio session after a gap.
        if let [.., (_, prev_end), (start, _)] = rows[..] {
            if start >= prev_end + 1 + SESSION_GAP {
                rows.pop();
            }
        }
        let &(_, last_end) = rows.last()?;
        Some(Toc {
            offsets: rows.iter().map(|(s, _)| s + LEAD_IN).collect(),
            lead_out: last_end + 1 + LEAD_IN,
        })
    }

    /// From the track starts and end of a single-file image of the whole
    /// disc, in seconds (cue sheet times are whole CD frames, so this is
    /// exact when the image wasn't trimmed).
    pub fn from_image(starts: &[f64], end: f64) -> Option<Toc> {
        let sector = |secs: f64| (secs * 75.0).round() as u32 + LEAD_IN;
        if starts.is_empty() || starts.len() > 99 || starts.first() != Some(&0.0) {
            return None;
        }
        Some(Toc {
            offsets: starts.iter().map(|&s| sector(s)).collect(),
            lead_out: sector(end),
        })
    }

    pub fn disc_id(&self) -> String {
        let mut s = format!("{:02X}{:02X}{:08X}", 1, self.offsets.len(), self.lead_out);
        for i in 0..99 {
            s += &format!("{:08X}", self.offsets.get(i).copied().unwrap_or(0));
        }
        base64(&Sha1::digest(s.as_bytes()))
    }

    /// `1+12+267257+150+...` for MusicBrainz's `toc` parameter (fuzzy lookup
    /// when the disc ID itself isn't known).
    pub fn param(&self) -> String {
        let mut parts = vec![
            "1".to_string(),
            self.offsets.len().to_string(),
            self.lead_out.to_string(),
        ];
        parts.extend(self.offsets.iter().map(u32::to_string));
        parts.join("+")
    }
}

impl Toc {
    /// `0:19528:...:282942` for the CueTools database: track offsets and the
    /// lead-out, without the lead-in.
    pub fn ctdb_param(&self) -> String {
        self.offsets
            .iter()
            .chain([&self.lead_out])
            .map(|o| (o - LEAD_IN).to_string())
            .collect::<Vec<_>>()
            .join(":")
    }
}

/// Base64 with MusicBrainz's URL-safe alphabet (`.`, `_`, `-` padding).
fn base64(bytes: &[u8]) -> String {
    const ABC: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._";
    let mut out = String::new();
    for chunk in bytes.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let n = (b[0] as u32) << 16 | (b[1] as u32) << 8 | b[2] as u32;
        for i in 0..4 {
            if i <= chunk.len() {
                out.push(ABC[(n >> (18 - 6 * i) & 63) as usize] as char);
            } else {
                out.push('-');
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disc_id_of_known_toc() {
        // Example from the MusicBrainz disc ID documentation.
        let toc = Toc {
            offsets: vec![150, 15363, 32314, 46592, 63414, 80489],
            lead_out: 95462,
        };
        assert_eq!(toc.disc_id(), "49HHV7Eb8UKF3aQiNmu1GR8vKTY-");
    }

    #[test]
    fn toc_from_eac_table() {
        let log = "TOC of the extracted CD\n\n     Track |   Start  |  Length  | Start sector | End sector \n    ---------------------------------------------------------\n        1  |  0:00.00 |  2:03.53 |         0    |     9277   \n        2  |  2:03.53 |  1:24.52 |      9278    |    15629   \n\nRange status";
        let toc = Toc::from_log(log).unwrap();
        assert_eq!(toc.offsets, vec![150, 9428]);
        assert_eq!(toc.lead_out, 15780);
    }
}
