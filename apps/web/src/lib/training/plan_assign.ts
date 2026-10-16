// Which of an athlete's plans a coach's assignment must clear (decisions
// § 2008): assign_plan_to_athlete refuses a window that shares a day with any
// of the athlete's active plans, and accepts any other. The coaching page
// reads every active plan the athlete holds and names the ones still ahead,
// so the coach can pick dates before the server has to refuse.
// Dart twin `apps/mobile_android/lib/plan_assign.dart` — keep the three
// helpers and the test counts in lockstep.

import { shiftIsoDate } from './plan_bulk_ops';
import { overlappingPlans } from './plan_current';
import { clonedPlanEndIso } from './plan_overlap';

export type PlanWindow = { name: string; start_date: string; end_date: string };

/// The athlete's active plans that still hold dates from `todayIso` on, in
/// start order. A plan that has already ended blocks nothing.
export function assignBlockers<T extends PlanWindow>(activePlans: readonly T[], todayIso: string): T[] {
	return activePlans
		.filter((p) => p.end_date >= todayIso)
		.sort((a, b) => (a.start_date < b.start_date ? -1 : a.start_date > b.start_date ? 1 : 0));
}

/// The first start date after every blocker, or today when none is ahead.
export function firstStartAfter(blockers: readonly PlanWindow[], todayIso: string): string {
	const lastEnd = blockers.reduce<string | null>((a, p) => (a == null || p.end_date > a ? p.end_date : a), null);
	if (lastEnd == null || lastEnd < todayIso) return todayIso;
	return shiftIsoDate(lastEnd, 1);
}

/// The blocker an assignment of `source` from `startIso` runs into — the one
/// that ends last, so "start after it ends" clears them all — or null.
export function assignCollision<T extends PlanWindow>(
	blockers: readonly T[],
	source: { start_date: string; end_date: string },
	startIso: string,
): T | null {
	const hits = overlappingPlans([...blockers], startIso, clonedPlanEndIso(source, startIso));
	return hits.reduce<T | null>((a, p) => (a == null || p.end_date > a.end_date ? p : a), null);
}
