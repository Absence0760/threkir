/// Pure window contract for the dashboard's recency run fetch, kept out
/// of `data.ts` so it is unit-testable (data.ts pulls in the supabase
/// singleton + `$env`, which the tsx test runner can't load).
///
/// The dashboard reasons only about *recent* training — the 90-day load
/// curve, the last-12-weeks consistency card, the race predictor's
/// recency-weighted anchor, this-week / goal roll-ups, the current streak
/// and the recent-runs list. A generous 2-year window covers all of them
/// while sparing the highest-traffic page the unbounded `select('*')`
/// history scan. Lifetime headline stats (total runs, longest run) are
/// served by a separate cheap aggregate, not this window.

export const DASHBOARD_RUNS_WINDOW_DAYS = 730;

/// The ISO-less Date cutoff `fetchRunsForDashboard` filters `started_at`
/// against: `now` minus the window. Callers pass the query's
/// `.gte('started_at', dashboardRunsWindowStart(new Date()).toISOString())`.
export function dashboardRunsWindowStart(now: Date): Date {
	const start = new Date(now);
	start.setDate(start.getDate() - DASHBOARD_RUNS_WINDOW_DAYS);
	return start;
}

export type PeriodType = 'week' | 'month' | 'all';

/// Whether a `PeriodSummary` period can be answered from a bounded run set.
///
/// The window above exists for the dashboard's recency cards, but the same
/// runs were also handed to the period drilldown — which offers an "all
/// time" tab and unbounded Previous/Next paging. A roll-up labelled "all
/// time" computed over ~2 years silently under-reports a deep history
/// (issue #664): the modal's totals disagreed with the lifetime aggregate
/// on the very stat card that opened it. `coveredFrom` is the earliest
/// instant the caller's run set is guaranteed to cover; `null` means the
/// caller already holds the complete history and never needs a re-fetch.
export function periodNeedsFullHistory(
	type: PeriodType,
	periodStart: Date,
	coveredFrom: Date | null,
): boolean {
	if (coveredFrom == null) return false;
	if (type === 'all') return true;
	return periodStart.getTime() < coveredFrom.getTime();
}

/// Which source chips the dashboard's filter row should offer.
///
/// The row used to render one chip per source in the vocabulary, so a runner
/// who has never touched Strava was offered a Strava filter that resolves to an
/// empty dashboard — on a deployment that may not be able to connect Strava at
/// all. That is the same class of claim the integrations page was making, in
/// the one place it still leaks: a control for something that isn't there.
///
/// Presence is measured against the runs the chips actually filter — the
/// dashboard's own window — rather than against what is configured, because a
/// deployment that later loses its Strava client ID must still let a runner
/// filter the Strava runs they already have.
///
/// The `all` chip is kept whenever anything is, and the whole row collapses
/// below two real sources: a lone "All / Recorded" pair is a filter with
/// nothing to filter between.
export function visibleRunSources<T extends { value: string }>(
	chips: readonly T[],
	runSources: Iterable<string | null | undefined>
): T[] {
	const present = new Set<string>();
	for (const source of runSources) {
		if (source) present.add(source);
	}
	if (present.size < 2) return [];
	return chips.filter((c) => c.value === 'all' || present.has(c.value));
}
