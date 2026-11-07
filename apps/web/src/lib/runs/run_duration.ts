/// How long one run can last, and the entry rules for a typed duration.
/// Shared with `packages/core_models/lib/src/run_duration.dart`: keep the two
/// in lockstep — constants, algorithm, edge cases, and test counts.
///
/// Nothing bounded a manual duration at any layer, so a runner who typed
/// "12333" into the Hours box saved a 2 km run lasting 12,333 hours and every
/// weekly total, recap and challenge that summed it read the same absurd
/// number (issue #1300 § 5, decisions § 2359).

/// Ten days. The longest single efforts this product records are multi-day
/// ultras — the Moab 240's cutoff is 112 h, the longest plausible push about
/// five days — so ten days refuses no real activity and refuses every typo
/// that lands an hours figure in the thousands. `runs_duration_s_max_check`
/// on the server holds the same literal.
export const MAX_RUN_DURATION_S = 864_000;

/// 1 km/h. A typed duration this slow for its distance is almost certainly a
/// figure in the wrong box, so the form asks before saving rather than
/// refusing: the slowest legitimate whole-activity pace is a steep alpine hike
/// (Naismith: about 600 m of climbing an hour), still above 1.4 km/h over the
/// ground, and a 240-mile ultra finishing at its 112 h cutoff averages 3.4 km/h.
export const SLOW_PACE_CONFIRM_S_PER_KM = 3600;

/// Input widths. Three hour digits hold 240 h, the whole bound; two are the
/// most 0–59 ever needs.
export const HOURS_MAX_DIGITS = 3;
export const MINUTES_SECONDS_MAX_DIGITS = 2;

export type ManualDurationError =
	| 'invalid'
	| 'minutesOutOfRange'
	| 'secondsOutOfRange'
	| 'zero'
	| 'tooLong';

export type ManualDurationResult =
	| { ok: true; seconds: number }
	| { ok: false; error: ManualDurationError };

const DIGITS = /^\d*$/;

/// Past nine significant digits a box is over every bound, and Dart's
/// `int.parse` would throw where `Number` returns Infinity — so both halves
/// read it as this one value instead.
const OVERFLOW = 1_000_000_000;

function part(raw: string): number | null {
	const t = raw.trim();
	if (!DIGITS.test(t)) return null;
	if (t.replace(/^0+/, '').length > 9) return OVERFLOW;
	return t === '' ? 0 : Number(t);
}

/// Grade the three boxes of a typed duration. An empty box reads as 0; any
/// character other than a digit is `invalid`, so a sign or a decimal point can
/// never be read as something else. Minutes and seconds are clock fields, 0–59.
export function validateManualDuration(
	hours: string,
	minutes: string,
	seconds: string,
): ManualDurationResult {
	const h = part(hours);
	const m = part(minutes);
	const s = part(seconds);
	if (h === null || m === null || s === null) return { ok: false, error: 'invalid' };
	if (m > 59) return { ok: false, error: 'minutesOutOfRange' };
	if (s > 59) return { ok: false, error: 'secondsOutOfRange' };
	const total = h * 3600 + m * 60 + s;
	if (total <= 0) return { ok: false, error: 'zero' };
	if (total > MAX_RUN_DURATION_S) return { ok: false, error: 'tooLong' };
	return { ok: true, seconds: total };
}

/// The read-side bound: a stored duration a total may sum. A row outside it
/// predates the CHECK (or reached the table before it was validated) and
/// contributes nothing to a duration aggregate rather than swamping it.
export function isPlausibleRunDuration(durationS: number): boolean {
	return Number.isFinite(durationS) && durationS >= 0 && durationS <= MAX_RUN_DURATION_S;
}

/// Whether a typed duration is slower than `SLOW_PACE_CONFIRM_S_PER_KM` over
/// its distance. False with no distance — there is no pace to judge.
export function isImplausiblySlow(durationS: number, distanceM: number): boolean {
	if (!(distanceM > 0) || !(durationS > 0)) return false;
	return durationS / (distanceM / 1000) > SLOW_PACE_CONFIRM_S_PER_KM;
}
