import { weekLead, type LeadActivity } from './week_lead';
import type { WeekStart } from './current_week';

/// Today's one progress summary card (issue #1374, decisions § 2492; the web
/// twin of mobile's `_progressSummary`): this week's and this calendar
/// month's distance. The week is `weekLead`'s own figure, so it matches the
/// Progress page's week lead to the metre; the streak comes from the streak
/// card's state, not from here.
export function progressSummary(input: {
	activities: readonly LeadActivity[];
	weekStart: WeekStart;
	now: Date;
}): { weekM: number; monthM: number } {
	const monthStart = new Date(input.now.getFullYear(), input.now.getMonth(), 1);
	let monthM = 0;
	for (const a of input.activities) {
		if (new Date(a.started_at) >= monthStart) monthM += a.distance_m;
	}
	const week = weekLead({
		activities: [...input.activities],
		planWorkouts: null,
		weeklyGoal: null,
		weekStart: input.weekStart,
		now: input.now,
	});
	return { weekM: week.distanceM, monthM };
}
