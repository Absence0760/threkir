/**
 * What leads Home, and which trend groups the runner has hidden from it
 * (#1187). Parity pair with `apps/mobile_android/lib/dashboard_layout.dart`;
 * the rules are the pair's point, the rendering is each platform's own.
 */

/**
 * The state the adaptive Today hero renders. A plan outranks everything,
 * because a plan written for today is the most specific thing Home knows;
 * a brand-new account without a plan gets the first-run block; otherwise a run
 * logged today leads, and failing that readiness plus a prompt to start.
 */
export type TodayHeroState =
	| 'race_day'
	| 'plan_today'
	| 'rest_day'
	| 'new_account'
	| 'ran_today'
	| 'no_plan';

export interface TodayHeroInputs {
	hasPlan: boolean;
	/// The plan's race is today (its end date, or a chained race dated today).
	raceToday: boolean;
	/// Today's plan workout kind, or null when the plan schedules nothing today.
	todayWorkoutKind: string | null;
	isNewAccount: boolean;
	/// A run started on the local calendar day.
	ranToday: boolean;
}

export function todayHeroState(i: TodayHeroInputs): TodayHeroState {
	if (i.hasPlan) {
		if (i.raceToday) return 'race_day';
		if (i.todayWorkoutKind != null && i.todayWorkoutKind !== 'rest') return 'plan_today';
		return 'rest_day';
	}
	if (i.isNewAccount) return 'new_account';
	if (i.ranToday) return 'ran_today';
	return 'no_plan';
}

/// Universal settings key holding the trend groups hidden from Home.
export const DASHBOARD_HIDDEN_CARDS_KEY = 'dashboard_hidden_cards';

/// The trend groups a runner can hide, in Home's order. The ids are the
/// `dashboard_trends` disclosure keys, so one group has one name everywhere.
export const HIDEABLE_DASHBOARD_CARDS = [
	'volume',
	'fitness',
	'performance',
	'effort',
	'recent',
] as const;

export type HideableDashboardCard = (typeof HIDEABLE_DASHBOARD_CARDS)[number];

export function isHideableDashboardCard(v: unknown): v is HideableDashboardCard {
	return typeof v === 'string' && (HIDEABLE_DASHBOARD_CARDS as readonly string[]).includes(v);
}

/**
 * The stored list as Home reads it: known ids only, each once, in Home's
 * order. Anything else (a non-array, an id a newer client wrote, a number)
 * is dropped rather than thrown on, so a bad bag never takes a card away
 * that the runner did not hide.
 */
export function parseHiddenCards(raw: unknown): HideableDashboardCard[] {
	if (!Array.isArray(raw)) return [];
	const present = new Set(raw.filter(isHideableDashboardCard));
	return HIDEABLE_DASHBOARD_CARDS.filter((id) => present.has(id));
}

/// [list] with [id] hidden or shown, normalised the way [parseHiddenCards] reads it.
export function withCardHidden(
	list: readonly string[],
	id: HideableDashboardCard,
	hidden: boolean,
): HideableDashboardCard[] {
	const next = new Set(parseHiddenCards([...list]));
	if (hidden) next.add(id);
	else next.delete(id);
	return HIDEABLE_DASHBOARD_CARDS.filter((c) => next.has(c));
}
