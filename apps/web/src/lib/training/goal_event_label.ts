import { formatDistance } from '#lib/format/units.svelte.ts';
import { m } from '#lib/i18n/store.svelte.ts';

/// The goal a plan trains for, as one label every plan surface shares (the
/// list, the library and its preview). A `custom` plan names its distance
/// when it has one: an ultra is stored as `custom` with `goal_distance_m`, and
/// "Custom" says nothing about a 50 km block.
export function goalEventLabel(goalEvent: string, goalDistanceM?: number | null): string {
	switch (goalEvent) {
		case 'distance_5k':
			return '5K';
		case 'distance_10k':
			return '10K';
		case 'distance_half':
			return m('plansPage.eventHalf');
		case 'distance_full':
			return m('plansPage.eventFull');
		default:
			return goalDistanceM && goalDistanceM > 0
				? formatDistance(goalDistanceM)
				: m('plansPage.eventCustom');
	}
}

/// "12 weeks · 4 days/week" — the plan-length fact in one string, so the
/// list, the library card and the library preview cannot drift apart.
export function planLengthLabel(weeks: number, daysPerWeek: number): string {
	return weeks === 1
		? m('plansPage.metaWeeksSingular', { days: daysPerWeek })
		: m('plansPage.metaWeeksPlural', { total: weeks, days: daysPerWeek });
}
