/// Pure week-bucketing for the dashboard weekly-mileage chart, extracted
/// from `fetchWeeklyMileage` so the year-stable keying is unit-testable.
///
/// Runs are grouped into weeks anchored on the user's `week_start_day`. The
/// bucket key is the week start's year-stable ISO date (`yyyy-mm-dd`): a
/// day/month-only key (e.g. "5 Jan") merged the same calendar week across
/// different years, fusing two New Year's weeks into a single bar. The human
/// `week` label stays in the prior `d MMM` form. Distance stays in metres;
/// render-time formatting honours the user's unit.
///
/// The output is a CONTINUOUS window: every one of the last `maxWeeks` weeks
/// gets a bucket, zero where nothing was run. It used to emit only the weeks
/// that had runs, which made the chart lie in both directions — a runner who
/// ran in one of the last twelve weeks got a single bar that read as their
/// whole training history, and a runner who took a fortnight off got two
/// adjacent bars with the gap silently closed up. A weekly-mileage chart's
/// subject is the weeks as much as the miles, and a week off is the most
/// load-bearing thing it can show.

export interface WeekBar {
	/// The full, localised week label — what a reader hovers for.
	week: string;
	/// The short label the x-axis has room for, formatted in its OWN right
	/// rather than cut out of `week`. The chart used to render
	/// `week.split(' ')[0]`, which is day-first order assumed as a universal:
	/// "31 Aug" gives "31", but en-US gives "Aug" for every week of August,
	/// de gives "31." and ja ("8月31日") has no space to split at all, so the
	/// whole date landed under the bar. A formatted string is not a record
	/// with fields; it is prose in someone's language.
	axis: string;
	distance_m: number;
}

export function bucketWeeklyMileage(
	runs: { started_at: string; distance_m: number }[],
	maxWeeks = 12,
	locale?: string,
	weekStartDay: 'monday' | 'sunday' = 'monday',
	/// The window's right-hand edge. Injected rather than read from the clock
	/// so a test can pin the window its fixtures sit in — the same reason the
	/// dashboard threads a `now` into its week strip and streak cards.
	now: Date = new Date(),
): WeekBar[] {
	/// Midnight at the start of the week containing `d`.
	/// getDay(): 0 = Sunday … 6 = Saturday.
	const weekStartOf = (d: Date): Date => {
		const start = new Date(d);
		const offset = weekStartDay === 'sunday' ? d.getDay() : (d.getDay() + 6) % 7;
		start.setDate(d.getDate() - offset);
		start.setHours(0, 0, 0, 0);
		return start;
	};

	const isoKey = (d: Date): string =>
		`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

	const currentWeek = weekStartOf(now);
	type Slot = { distance_m: number; label: string; axis: string };
	const slots: Slot[] = [];
	const byKey = new Map<string, Slot>();

	for (let back = maxWeeks - 1; back >= 0; back--) {
		const start = new Date(currentWeek);
		start.setDate(currentWeek.getDate() - back * 7);
		// The KEY stays year-stable ISO (locale-independent); only the human
		// axis label is localised (i18n-readiness W-10 — the label was pinned
		// to en-GB). `locale` is the active UI locale; undefined falls back to
		// the runtime default.
		const slot = {
			distance_m: 0,
			label: start.toLocaleDateString(locale, { day: 'numeric', month: 'short' }),
			axis: start.toLocaleDateString(locale, { day: 'numeric' }),
		};
		slots.push(slot);
		byKey.set(isoKey(start), slot);
	}

	// A run outside the window is dropped rather than clamped into the edge
	// bucket: the caller queries a 14-week window (12 + a 2-week buffer for
	// partial edges), so the overflow is real data that belongs to weeks this
	// chart does not cover.
	let inWindow = 0;
	for (const run of runs) {
		const slot = byKey.get(isoKey(weekStartOf(new Date(run.started_at))));
		if (!slot) continue;
		slot.distance_m += run.distance_m;
		inWindow++;
	}

	// Nothing in the window means no chart at all, not a row of empty slots:
	// the dashboard renders its own "no mileage yet" copy on an empty array,
	// which is the honest thing to show a new account (and the thing twelve
	// zero-height bars would replace with a broken-looking axis).
	if (inWindow === 0) return [];

	return slots.map((s) => ({
		week: s.label,
		axis: s.axis,
		distance_m: Math.round(s.distance_m),
	}));
}
