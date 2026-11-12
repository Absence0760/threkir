/// Shaping for the operator's Home metrics page (/admin/home-metrics, issue
/// #1362). Weeks are ISO weeks (Monday start) in UTC, as the RPCs count them.

/** The day the redesigned Home shipped (decisions § 2387). A Sunday, so its
 *  ISO week (from Monday 2 November) is mostly the old Home. */
export const HOME_REDESIGN_DATE = '2026-11-08';

function utcDay(iso: string): number {
	return Date.parse(`${iso}T00:00:00Z`);
}

/** Whether the ISO week starting `weekStart` (YYYY-MM-DD) contains `day`. */
export function weekContains(weekStart: string, day: string): boolean {
	const start = utcDay(weekStart);
	const d = utcDay(day);
	if (Number.isNaN(start) || Number.isNaN(d)) return false;
	return d >= start && d < start + 7 * 86_400_000;
}

/** Whether `weekStart` is the UTC ISO week `now` falls in. */
export function isCurrentWeek(weekStart: string, now: Date): boolean {
	return weekContains(weekStart, now.toISOString().slice(0, 10));
}

/** "2 Nov 2026" in the reader's locale, read as a UTC date. */
export function formatWeekStart(weekStart: string, locale: string): string {
	const instant = utcDay(weekStart);
	if (Number.isNaN(instant)) return weekStart;
	return new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' }).format(
		instant,
	);
}

/** A one-decimal percentage, or null when the week had no denominator. */
export function formatPct(pct: number | null, locale: string): string | null {
	if (pct === null || !Number.isFinite(pct)) return null;
	return new Intl.NumberFormat(locale, { style: 'percent', minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(
		pct / 100,
	);
}
