//! Judges a parsed log with the user's [RipRules]: which deductions flag it,
//! when AccurateRip mismatches count and what "perfect" takes. Works on the
//! stored log alone, so rule changes apply without reading logs again.

use super::score::{is_error, KINDS};
use album_model::{DeductionKind, LogChecksum, RipLog, RipRules, RipStatus};

pub fn default_rules() -> RipRules {
    RipRules {
        problem_kinds: KINDS
            .iter()
            .filter(|k| k.3 && !k.4)
            .map(|k| k.0.to_string())
            .collect(),
        ar_mismatch_min_submissions: 0,
        invalid_signature_is_problem: true,
        perfect_min_confidence: 1,
        perfect_needs_both: false,
    }
}

/// The deductions the user can count as problems or not (rip errors always
/// make a log an error).
pub fn deduction_kinds() -> Vec<DeductionKind> {
    KINDS
        .iter()
        .filter(|k| !k.4)
        .map(|&(id, label, points, problem, _)| DeductionKind {
            id: id.into(),
            label: label.into(),
            points,
            problem_by_default: problem,
        })
        .collect()
}

/// Why the log is flagged under the rules; empty when it isn't.
pub fn problems(log: &RipLog, rules: &RipRules) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for d in log
        .deductions
        .iter()
        .filter(|d| !d.informational && !is_error(&d.kind))
    {
        if !out.contains(&d.message) {
            out.push(d.message.clone());
        }
    }
    let min = rules.ar_mismatch_min_submissions as i32;
    let mismatched = log
        .tracks
        .iter()
        .filter(|t| {
            min > 0 && t.accurate_rip_ok == Some(false) && t.ar_confidence.unwrap_or(0) >= min
        })
        .count();
    if mismatched > 0 {
        out.push(format!("{mismatched} 条音轨与 AccurateRip 数据库不一致"));
    }
    if rules.invalid_signature_is_problem && log.checksum == LogChecksum::Invalid {
        out.push("日志签名不符，可能被修改过".into());
    }
    out
}

pub fn judge(log: &mut RipLog, rules: &RipRules) {
    for d in &mut log.deductions {
        d.informational = !is_error(&d.kind) && !rules.problem_kinds.contains(&d.kind);
    }
    log.status = if log.score.is_none() {
        RipStatus::Unknown
    } else if log.errors {
        RipStatus::Error
    } else if !problems(log, rules).is_empty() {
        RipStatus::Warning
    } else if perfect(log, rules) {
        RipStatus::Perfect
    } else {
        RipStatus::Good
    };
}

fn perfect(log: &RipLog, rules: &RipRules) -> bool {
    let tracks = &log.tracks;
    if tracks.is_empty() {
        return false;
    }
    let min = rules.perfect_min_confidence.max(1) as i32;
    let ar = tracks
        .iter()
        .all(|t| t.accurate_rip_ok == Some(true) && t.ar_confidence.unwrap_or(1) >= min);
    let has_ctdb = tracks.iter().any(|t| t.ctdb_ok.is_some());
    let ctdb = has_ctdb && tracks.iter().all(|t| t.ctdb_ok == Some(true));
    if rules.perfect_needs_both {
        ar && (!has_ctdb || ctdb)
    } else {
        ar || ctdb
    }
}
