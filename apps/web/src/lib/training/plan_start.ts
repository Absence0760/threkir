// The plan wizard's start-date alignment. The plan generator (training.ts)
// hard-anchors day 0 of the start week to the Sunday long run — every day
// role is an OFFSET from the start date, not a real weekday — so a plan's
// start date must be a Sunday or every day-role shifts.
//
// The beginner walk-run plan is the one exemption. Its sessions sit at
// offsets 0/2/4 with rest between and no long run, so no day role is tied to
// a weekday and nothing shifts when it starts midweek. Holding a brand-new
// runner 7-13 days for a Sunday they do not need is the cost the exemption
// removes: a walk-run plan may start today, and defaults to tomorrow.
//
// Its own pair rather than part of training.ts ↔ training.dart: this is
// wizard-input ergonomics, not generator algorithm. Dart twin
// `apps/mobile_android/lib/plan_start.dart` takes a `DateTime` where this
// side takes the ISO string an `<input type="date">` yields; that input type
// is the only difference.

/// Snap an ISO `yyyy-mm-dd` date forward to the upcoming Sunday — a no-op
/// when it already is one. Parsed at local midnight so the weekday matches
/// what the user sees in their own timezone.
export function nextSundayIso(iso: string): string {
	const d = new Date(iso + 'T00:00:00');
	const off = (7 - d.getDay()) % 7;
	d.setDate(d.getDate() + off);
	const y = d.getFullYear();
	const m = String(d.getMonth() + 1).padStart(2, '0');
	const day = String(d.getDate()).padStart(2, '0');
	return `${y}-${m}-${day}`;
}

/// True when an ISO date falls on a Sunday (local time).
export function isSundayIso(iso: string): boolean {
	return new Date(iso + 'T00:00:00').getDay() === 0;
}

function addDaysIso(iso: string, days: number): string {
	const d = new Date(iso + 'T00:00:00');
	d.setDate(d.getDate() + days);
	const y = d.getFullYear();
	const m = String(d.getMonth() + 1).padStart(2, '0');
	const day = String(d.getDate()).padStart(2, '0');
	return `${y}-${m}-${day}`;
}

/// Whether a plan of this shape may start on this date. Every date is
/// allowed for a walk-run plan; any other plan needs a Sunday.
export function planStartAllowedIso(iso: string, walkRun: boolean): boolean {
	return walkRun || isSundayIso(iso);
}

/// The date a typed or picked start lands on: unchanged for a walk-run plan,
/// snapped forward to the upcoming Sunday for any other.
export function alignPlanStartIso(iso: string, walkRun: boolean): string {
	return walkRun ? iso : nextSundayIso(iso);
}

/// The wizard's default start. A walk-run plan starts tomorrow, which leaves
/// today to get ready without making the runner wait. Any other plan starts
/// on the Sunday at least a week out, so the first long run has a week's
/// notice.
export function defaultPlanStartIso(todayIso: string, walkRun: boolean): string {
	return walkRun ? addDaysIso(todayIso, 1) : nextSundayIso(addDaysIso(todayIso, 7));
}
