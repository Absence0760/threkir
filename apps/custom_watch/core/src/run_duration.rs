//! The ten-day run bound — a one-way port of `isPlausibleRunDuration` from the
//! `run_duration` parity pair (`apps/web/src/lib/runs/run_duration.ts`,
//! decisions § 2359). Only the read-side predicate is ported: the watch has no
//! typed-duration entry, so `validateManualDuration` has nothing to grade here.

/// Ten days, the same literal as `runs_duration_s_max_check`.
pub const MAX_RUN_DURATION_S: f64 = 864_000.0;

/// A stored duration a total may sum. A run outside it adds no time to a
/// duration aggregate, though it still counts as a run and its distance stands.
/// The bound itself is outside: exactly ten days is the placeholder the
/// 20271218000002 repair stored over an out-of-bound row (decisions § 2464).
pub fn is_plausible_run_duration(duration_s: f64) -> bool {
    duration_s.is_finite() && (0.0..MAX_RUN_DURATION_S).contains(&duration_s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn is_zero_up_to_but_not_including_the_bound() {
        assert!(is_plausible_run_duration(0.0));
        assert!(is_plausible_run_duration(863_999.0));
        assert!(!is_plausible_run_duration(864_000.0));
        assert!(!is_plausible_run_duration(44_400_094.0));
        assert!(!is_plausible_run_duration(-1.0));
        assert!(!is_plausible_run_duration(f64::NAN));
    }
}
