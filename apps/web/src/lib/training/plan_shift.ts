// What shifting a plan's dates does to the runner's other active plans, before
// shift_training_plan runs (decisions § 2052). Active plans may not share a day
// (training_plans_active_no_overlap, § 2008), so a shift that lands on another
// active plan would fail with 23P01. Forward, the plans queued after this one
// can move with it — the RPC's p_shift_following moves every active plan that
// starts after this one ends, by the same number of days, so their spacing
// holds. Backward, the plan before it is history the runner is standing on, so
// a shift into it is refused rather than dragging that plan along.

import { shiftIsoDate } from './plan_bulk_ops';
import { overlappingPlans } from './plan_current';

type PlanWindow = { id: string; start_date: string; end_date: string };

export type PlanShiftImpact<T extends PlanWindow> =
	/// Nothing else is in the way.
	| { kind: 'clear' }
	/// The new window lands on a plan queued after this one. `following` is
	/// every active plan the RPC would move with p_shift_following, in start
	/// order; it includes plans the new window does not reach, because moving
	/// only the reached ones would close the gaps after them.
	| { kind: 'following'; following: T[] }
	/// The new window lands on a plan before this one. Refused.
	| { kind: 'blocked'; blocking: T[] };

/// `plan` is the plan being shifted, `others` the runner's other active plans
/// (the plan itself is ignored if present). A plan that is not active does not
/// hold dates against anything, so it always shifts clear.
export function planShiftImpact<T extends PlanWindow>(
	plan: PlanWindow & { status: string },
	others: T[],
	days: number
): PlanShiftImpact<T> {
	if (days === 0 || plan.status !== 'active') return { kind: 'clear' };
	const newStart = shiftIsoDate(plan.start_date, days);
	const newEnd = shiftIsoDate(plan.end_date, days);
	const rest = others.filter((p) => p.id !== plan.id);
	if (days < 0) {
		const earlier = rest.filter((p) => p.end_date < plan.start_date);
		const blocking = overlappingPlans(earlier, newStart, newEnd);
		return blocking.length > 0 ? { kind: 'blocked', blocking } : { kind: 'clear' };
	}
	const later = rest
		.filter((p) => p.start_date > plan.end_date)
		.sort((a, b) => (a.start_date < b.start_date ? -1 : a.start_date > b.start_date ? 1 : 0));
	if (overlappingPlans(later, newStart, newEnd).length === 0) return { kind: 'clear' };
	return { kind: 'following', following: later };
}
