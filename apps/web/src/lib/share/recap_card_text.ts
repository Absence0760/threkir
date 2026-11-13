/// The words and numbers the recap share image prints, localised by the
/// caller's `t` (the page passes the i18n store's `m`) and formatted once, so
/// the image builder only places strings. Twin of `recapCardText` in
/// apps/mobile_android/lib/widgets/recap_share_card.dart: the same six cells
/// in the same order.

import { RECAP_BADGE_IDS, type RecapBadge, type RecapBadgeId, type YearInRunningRecap } from '../runs/recap';
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

/// A badge's words: its label, and the detail line with the badge's `value`
/// in it (`n` for a count, `time` for a start time).
const RECAP_BADGE_TEXT: Record<RecapBadgeId, { label: MessageKey; detail: MessageKey; param?: 'n' | 'time' }> = {
	'dist-2000': { label: 'recap.badgeLabel_dist2000', detail: 'recap.badgeDetail_dist2000' },
	'dist-1000': { label: 'recap.badgeLabel_dist1000', detail: 'recap.badgeDetail_dist1000' },
	'dist-500': { label: 'recap.badgeLabel_dist500', detail: 'recap.badgeDetail_dist500' },
	'dist-100': { label: 'recap.badgeLabel_dist100', detail: 'recap.badgeDetail_dist100' },
	'runs-200': { label: 'recap.badgeLabel_runs200', detail: 'recap.badgeDetail_runs200' },
	'runs-100': { label: 'recap.badgeLabel_runs100', detail: 'recap.badgeDetail_runs100' },
	'runs-50': { label: 'recap.badgeLabel_runs50', detail: 'recap.badgeDetail_runs50' },
	'long-ultra': { label: 'recap.badgeLabel_longUltra', detail: 'recap.badgeDetail_longUltra' },
	'long-marathon': { label: 'recap.badgeLabel_longMarathon', detail: 'recap.badgeDetail_longMarathon' },
	'long-half': { label: 'recap.badgeLabel_longHalf', detail: 'recap.badgeDetail_longHalf' },
	'streak-30': { label: 'recap.badgeLabel_streak30', detail: 'recap.badgeDetail_streak', param: 'n' },
	'streak-14': { label: 'recap.badgeLabel_streak14', detail: 'recap.badgeDetail_streak', param: 'n' },
	'streak-7': { label: 'recap.badgeLabel_streak7', detail: 'recap.badgeDetail_streak', param: 'n' },
	'elev-everest': { label: 'recap.badgeLabel_elevEverest', detail: 'recap.badgeDetail_elevEverest' },
	'elev-5000': { label: 'recap.badgeLabel_elev5000', detail: 'recap.badgeDetail_elev5000' },
	'months-12': { label: 'recap.badgeLabel_months12', detail: 'recap.badgeDetail_months12' },
	'months-6': { label: 'recap.badgeLabel_months6', detail: 'recap.badgeDetail_months6', param: 'n' },
	'pr-5': { label: 'recap.badgeLabel_pr5', detail: 'recap.badgeDetail_pr', param: 'n' },
	'pr-1': { label: 'recap.badgeLabel_pr1', detail: 'recap.badgeDetail_pr', param: 'n' },
	'photo-25': { label: 'recap.badgeLabel_photo25', detail: 'recap.badgeDetail_photo', param: 'n' },
	'photo-1': { label: 'recap.badgeLabel_photo1', detail: 'recap.badgeDetail_photo', param: 'n' },
	variety: { label: 'recap.badgeLabel_variety', detail: 'recap.badgeDetail_variety', param: 'n' },
	early: { label: 'recap.badgeLabel_early', detail: 'recap.badgeDetail_early', param: 'time' },
	night: { label: 'recap.badgeLabel_night', detail: 'recap.badgeDetail_night', param: 'time' },
};

export function recapBadgeText(b: RecapBadge, t: RecapTranslate): { label: string; detail: string } {
	const k = RECAP_BADGE_TEXT[b.id];
	const label = t(k.label);
	if (!k.param) return { label, detail: t(k.detail) };
	if (b.value == null) return { label, detail: '' };
	return { label, detail: t(k.detail, { [k.param]: b.value }) };
}

const isBadgeId = (id: unknown): id is RecapBadgeId =>
	typeof id === 'string' && (RECAP_BADGE_IDS as readonly string[]).includes(id);

/// A badge as a published `public_recaps` snapshot stores it. Snapshots
/// published before the words moved to the catalogue carry an English
/// `detail` ("47 days in a row", "Out at 22:15") and no `value`; the value is
/// read back out of that line, which only ever held one number or one time,
/// so an old snapshot reads in its reader's language too. An id this build
/// does not know is dropped rather than shown as a bare id.
export function recapBadgeFromSnapshot(raw: unknown): RecapBadge | null {
	if (!raw || typeof raw !== 'object') return null;
	const o = raw as Record<string, unknown>;
	if (!isBadgeId(o.id)) return null;
	const icon = typeof o.icon === 'string' ? o.icon : 'emoji_events';
	const param = RECAP_BADGE_TEXT[o.id].param;
	if (!param) return { id: o.id, icon };
	let value: number | string | undefined;
	if (param === 'n' && typeof o.value === 'number' && Number.isFinite(o.value)) value = o.value;
	else if (param === 'time' && typeof o.value === 'string') value = o.value;
	else if (typeof o.detail === 'string') {
		const hit = param === 'time' ? o.detail.match(/\b\d{1,2}:\d{2}\b/) : o.detail.match(/\d+/);
		if (hit) value = param === 'time' ? hit[0] : Number(hit[0]);
	}
	return value == null ? { id: o.id, icon } : { id: o.id, icon, value };
}

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
