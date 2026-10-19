//! Minimal CUE sheet parser.

#[derive(Debug, Default, Clone)]
pub struct CueTrack {
    pub number: i32,
    pub title: Option<String>,
    pub performer: Option<String>,
    /// INDEX 01 in seconds, relative to `file`.
    pub start: f64,
    /// Index into `CueSheet::files`.
    pub file: usize,
}

#[derive(Debug, Default, Clone)]
pub struct CueSheet {
    pub title: Option<String>,
    pub performer: Option<String>,
    pub genre: Option<String>,
    pub date: Option<String>,
    pub disc_number: Option<i32>,
    pub files: Vec<String>,
    pub tracks: Vec<CueTrack>,
}

/// Splits a cue line argument, honouring double quotes.
fn arg(rest: &str) -> String {
    let rest = rest.trim();
    if let Some(stripped) = rest.strip_prefix('"') {
        match stripped.rfind('"') {
            Some(end) => stripped[..end].to_string(),
            None => stripped.to_string(),
        }
    } else {
        rest.to_string()
    }
}

/// "FILE "name.wav" WAVE" -> name.wav
fn file_arg(rest: &str) -> String {
    let rest = rest.trim();
    if rest.starts_with('"') {
        return arg(rest);
    }
    // Unquoted: drop trailing type keyword.
    match rest.rsplit_once(' ') {
        Some((name, _)) => name.trim().to_string(),
        None => rest.to_string(),
    }
}

fn msf(s: &str) -> Option<f64> {
    let mut it = s.trim().split(':');
    let m: f64 = it.next()?.parse().ok()?;
    let sec: f64 = it.next()?.parse().ok()?;
    let f: f64 = it.next()?.parse().ok()?;
    Some(m * 60.0 + sec + f / 75.0)
}

fn non_empty(s: String) -> Option<String> {
    if s.trim().is_empty() {
        None
    } else {
        Some(s)
    }
}

pub fn parse(text: &str) -> CueSheet {
    let mut cue = CueSheet::default();
    let mut current: Option<CueTrack> = None;
    for raw in text.lines() {
        let line = raw.trim();
        let (cmd, rest) = line.split_once(char::is_whitespace).unwrap_or((line, ""));
        match cmd.to_ascii_uppercase().as_str() {
            "REM" => {
                let (key, val) = rest
                    .trim()
                    .split_once(char::is_whitespace)
                    .unwrap_or((rest, ""));
                match key.to_ascii_uppercase().as_str() {
                    "GENRE" => cue.genre = non_empty(arg(val)),
                    "DATE" => cue.date = non_empty(arg(val)),
                    "DISCNUMBER" => cue.disc_number = arg(val).parse().ok(),
                    _ => {}
                }
            }
            "FILE" => cue.files.push(file_arg(rest)),
            "TRACK" => {
                if let Some(t) = current.take() {
                    cue.tracks.push(t);
                }
                let num = rest
                    .split_whitespace()
                    .next()
                    .and_then(|n| n.parse().ok())
                    .unwrap_or(0);
                let is_audio = rest.to_ascii_uppercase().contains("AUDIO");
                if is_audio {
                    current = Some(CueTrack {
                        number: num,
                        file: cue.files.len().saturating_sub(1),
                        ..Default::default()
                    });
                }
            }
            "TITLE" => match current.as_mut() {
                Some(t) => t.title = non_empty(arg(rest)),
                None => cue.title = non_empty(arg(rest)),
            },
            "PERFORMER" => match current.as_mut() {
                Some(t) => t.performer = non_empty(arg(rest)),
                None => cue.performer = non_empty(arg(rest)),
            },
            "INDEX" => {
                if let Some(t) = current.as_mut() {
                    let mut it = rest.split_whitespace();
                    if it.next().map(|i| i == "01" || i == "1").unwrap_or(false) {
                        if let Some(sec) = it.next().and_then(msf) {
                            t.start = sec;
                            // A track's INDEX 01 may live in a later FILE than its TRACK line.
                            t.file = cue.files.len().saturating_sub(1);
                        }
                    }
                }
            }
            _ => {}
        }
    }
    if let Some(t) = current.take() {
        cue.tracks.push(t);
    }
    cue
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_basic_sheet() {
        let cue = parse(
            "REM GENRE Soundtrack\nREM DATE 2018\nPERFORMER \"Qruppo\"\nTITLE \"Album\"\nFILE \"Disc_1.wav\" WAVE\n  TRACK 01 AUDIO\n    TITLE \"One\"\n    INDEX 01 00:00:00\n  TRACK 02 AUDIO\n    TITLE \"Two\"\n    PERFORMER \"Someone\"\n    INDEX 00 03:20:00\n    INDEX 01 03:24:02\n",
        );
        assert_eq!(cue.title.as_deref(), Some("Album"));
        assert_eq!(cue.performer.as_deref(), Some("Qruppo"));
        assert_eq!(cue.files, vec!["Disc_1.wav"]);
        assert_eq!(cue.tracks.len(), 2);
        assert!((cue.tracks[1].start - (204.0 + 2.0 / 75.0)).abs() < 1e-9);
        assert_eq!(cue.tracks[1].performer.as_deref(), Some("Someone"));
    }
}
