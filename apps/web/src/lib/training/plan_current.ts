// Which of a runner's active plans is "the" plan, now that several can be
// active at once as long as their windows do not overlap (plan chaining,
// decisions § 2008). Dart twin `apps/mobile_android/lib/plan_current.dart`;
// the SQL twin is the `active_plan` ordering in coach_roster_summary
// (migration 20270830000001), which returns `current ?? upcoming`.

type PlanWindow = { start_date: string; end_date: string };

/// `current` is the plan whose inclusive window covers `todayIso`; failing
/// that, the plan that ended most recently, so a finished block still reads as
/// the runner's plan until the next one starts. `upcoming` is the plan with the
/// earliest start after today that is not `current`. Dates are ISO
/// `yyyy-mm-dd`, which compare correctly as strings. Ties keep the earlier
/// element; the exclusion constraint makes them impossible among active rows.
export function pickCurrentPlan<T extends PlanWindow>(
	activePlans: T[],
	todayIso: string
): { current: T | null; upcoming: T | null } {
	let covering: T | null = null;
	let ended: T | null = null;
	let upcoming: T | null = null;
	for (const p of activePlans) {
		if (p.start_date <= todayIso && todayIso <= p.end_date) {
			if (!covering) covering = p;
		} else if (p.end_date < todayIso) {
			if (!ended || p.end_date > ended.end_date) ended = p;
		} else if (!upcoming || p.start_date < upcoming.start_date) {
			upcoming = p;
		}
	}
	return { current: covering ?? ended, upcoming };
}

/// `anchor` and the plans in `plans` that start after it ends, in date order:
/// the blocks chained behind it (decisions § 2008). Active plans cannot
/// overlap, so among active plans these are exactly the ones queued after the
/// anchor; a plan that starts inside the anchor's window is left out, which
/// keeps the result non-overlapping when the anchor is not itself active.
/// Ties on start keep the input order.
export function plansFollowing<T extends PlanWindow>(anchor: T, plans: T[]): T[] {
	const later = plans
		.map((p, i) => ({ p, i }))
		.filter(({ p }) => p.start_date > anchor.end_date)
		.sort((a, b) =>
			a.p.start_date < b.p.start_date ? -1 : a.p.start_date > b.p.start_date ? 1 : a.i - b.i
		)
		.map(({ p }) => p);
	return [anchor, ...later];
}

/// The runner's season as the Coach reads it: the plan `pickCurrentPlan` names
/// (current, else upcoming) and the plans chained after it. Empty with no
/// active plan.
export function currentSeason<T extends PlanWindow>(activePlans: T[], todayIso: string): T[] {
	const { current, upcoming } = pickCurrentPlan(activePlans, todayIso);
	const anchor = current ?? upcoming;
	return anchor ? plansFollowing(anchor, activePlans) : [];
}

/// The plans whose inclusive window shares at least one day with
/// [startIso, endIso] — the rows training_plans_active_no_overlap would
/// reject a new active plan over.
export function overlappingPlans<T extends PlanWindow>(
	plans: T[],
	startIso: string,
	endIso: string
): T[] {
	return plans.filter((p) => p.start_date <= endIso && p.end_date >= startIso);
}

/// An `active` plan whose last day is behind `todayIso` (the runner's local
/// day): its dates have run out but nothing has written `completed`, which
/// only the runner confirming "Finish plan" does. A paused, completed or
/// abandoned plan is never finished in this sense, and the end day itself is
/// still inside the plan.
export function isPlanFinished(
	plan: { status: string; end_date: string },
	todayIso: string
): boolean {
	return plan.status === 'active' && plan.end_date < todayIso;
}

/// Where a planned workout stands against the runner's local day. `done` and
/// `skipped` are written facts; `missed` is derived, never stored: a past,
/// non-rest workout that is neither done nor skipped once its day has ended in
/// the runner's time zone. The scheduled day itself is never missed, so a
/// workout still due tonight reads `upcoming`. Done wins over skipped, which
/// the write layer keeps exclusive anyway.
export type PlanWorkoutStatus = 'done' | 'skipped' | 'missed' | 'upcoming' | 'rest';

export function planWorkoutStatus(
	wo: { scheduled_date: string; kind: string; completed: boolean; skipped: boolean },
	todayIso: string
): PlanWorkoutStatus {
	if (wo.completed) return 'done';
	if (wo.skipped) return 'skipped';
	if (wo.kind === 'rest') return 'rest';
	return wo.scheduled_date < todayIso ? 'missed' : 'upcoming';
}

export function isWorkoutMissed(
	wo: { scheduled_date: string; kind: string; completed: boolean; skipped: boolean },
	todayIso: string
): boolean {
	return planWorkoutStatus(wo, todayIso) === 'missed';
}
