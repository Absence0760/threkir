import { m } from '#lib/i18n/store.svelte.ts';
import { defaultPlanStartIso } from '#lib/training/plan_start.ts';
import { starterById, starterSummary } from '#lib/training/starter_plans.ts';

/// The localized name of a built-in starter plan. Literal `m()` keys so the
/// i18n parity tooling can see them.
export function starterName(id: string): string {
	switch (id) {
		case 'c25k':
			return m('plansNew.starterC25k');
		case 'half_12wk':
			return m('plansNew.starterHalf12');
		case 'marathon_16wk':
			return m('plansNew.starterMarathon16');
		default:
			return id;
	}
}

/// What a starter asks of the runner — "9 weeks · 3 days a week · 30–45 min
/// a session" — for the line under its name on every surface that offers it.
export function starterSummaryText(id: string): string | null {
	const summary = starterSummary(id);
	if (!summary) return null;
	const params = { weeks: summary.weeks, days: summary.daysPerWeek };
	return summary.sessionMinutes
		? m('plansNew.starterSummaryTimed', { ...params, ...summary.sessionMinutes })
		: m('plansNew.starterSummary', params);
}

/// When a starter picked today begins: tomorrow for the walk-run starter,
/// which has no weekday roles, otherwise the Sunday at least a week out
/// (decisions § 735).
export function starterStartIso(id: string, todayIso: string): string {
	return defaultPlanStartIso(todayIso, starterById(id)?.beginnerWalkRun ?? false);
}
