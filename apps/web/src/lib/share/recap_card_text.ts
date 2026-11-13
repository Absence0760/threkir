/// The words and numbers the recap share image prints, localised by the
/// caller's `t` (the page passes the i18n store's `m`) and formatted once, so
/// the image builder only places strings. Twin of `recapCardText` in
/// apps/mobile_android/lib/widgets/recap_share_card.dart: the same six cells
/// in the same order.

import type { YearInRunningRecap } from '../runs/recap';
import type { MessageKey } from '../i18n/messages';
import { DEFAULT_SITE_URL } from '../core/site_url';
import { formatHoursMinutes } from '../format/time';

export type RecapTranslate = (key: MessageKey, params?: Record<string, string | number>) => string;

export interface RecapCardCell {
	label: string;
	value: string;
}

export interface RecapCardText {
	kicker: string;
	hero: string;
	subhead: string;
	cells: RecapCardCell[];
	footer: string;
}

export const RECAP_SITE = new URL(DEFAULT_SITE_URL).host;

export function recapWholeDistance(meters: number, unit: 'km' | 'mi'): string {
	if (unit === 'mi') return `${(meters / 1609.344).toFixed(0)} mi`;
	return `${(meters / 1000).toFixed(0)} km`;
}

export function recapActiveMonths(recap: YearInRunningRecap): number {
	return recap.monthly.filter((m) => m.runCount > 0).length;
}

/// `periodLabel` (e.g. "March 2026") makes a monthly card; without it the
/// card is the year's. `locale` groups the climb figure and upper-cases the
/// kicker; undefined is the host default.
export function recapCardText(
	recap: YearInRunningRecap,
	unit: 'km' | 'mi',
	t: RecapTranslate,
	opts: { periodLabel?: string; locale?: string } = {},
): RecapCardText {
	const kicker = opts.periodLabel
		? t('recap.monthHeroKicker', { period: opts.periodLabel })
		: t('recap.heroKicker', { year: recap.year });
	return {
		kicker: kicker.toLocaleUpperCase(opts.locale),
		hero: recapWholeDistance(recap.totalDistanceM, unit),
		subhead: t('recap.acrossRuns', { n: recap.runCount }),
		cells: [
			{ label: t('recap.longestRun'), value: recapWholeDistance(recap.longestRunM, unit) },
			{ label: t('recap.cardOnFoot'), value: formatHoursMinutes(recap.totalDurationS) },
			{ label: t('recap.bestStreak'), value: t('recap.cardStreakDays', { n: recap.bestStreakDays }) },
			{ label: t('recap.topWeek'), value: recapWholeDistance(recap.topWeek?.distanceM ?? 0, unit) },
			{
				label: t('recap.cardClimbed'),
				value: `${new Intl.NumberFormat(opts.locale).format(Math.round(recap.totalElevationM))} m`,
			},
			{ label: t('recap.cardActiveMonths'), value: `${recapActiveMonths(recap)} / 12` },
		],
		footer: RECAP_SITE,
	};
}
