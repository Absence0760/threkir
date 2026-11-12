import type { MessageKey } from '#lib/i18n/messages.ts';

type Translate = (key: MessageKey, params?: Record<string, string | number>) => string;

/// The goal a plan trains for, as one label every plan surface shares (the
/// list, the library and its preview). A `custom` plan names its distance
/// when it has one: an ultra is stored as `custom` with `goal_distance_m`, and
/// "Custom" says nothing about a 50 km block.
///
/// The catalogue lookup and the unit-aware distance formatter arrive as
/// arguments: both live in runes modules the `tsx --test` runner cannot load,
/// and the branch choice here is what the parity pair with mobile's
/// `planGoalLabel` pins.
export function goalEventLabel(
	t: Translate,
	formatDistance: (metres: number) => string,
	goalEvent: string,
	goalDistanceM?: number | null,
): string {
	switch (goalEvent) {
		case 'distance_5k':
			return '5K';
		case 'distance_10k':
			return '10K';
		case 'distance_half':
			return t('plansPage.eventHalf');
		case 'distance_full':
			return t('plansPage.eventFull');
		default:
			return goalDistanceM && goalDistanceM > 0
				? formatDistance(goalDistanceM)
				: t('plansPage.eventCustom');
	}
}

/// "12 weeks · 4 days/week" — the plan-length fact in one string, so the
/// list, the library card and the library preview cannot drift apart.
export function planLengthLabel(t: Translate, weeks: number, daysPerWeek: number): string {
	return weeks === 1
		? t('plansPage.metaWeeksSingular', { days: daysPerWeek })
		: t('plansPage.metaWeeksPlural', { total: weeks, days: daysPerWeek });
}
