import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildRecapShareSvg } from './recap_share_image';
import { recapCardText } from './recap_card_text';
import type { YearInRunningRecap } from '../runs/recap';
import { en } from '../i18n/locales/en';
import { messages as de } from '../i18n/locales/de';
import { interpolate } from '../i18n/interpolate';
import type { MessageKey } from '../i18n/messages';

const tIn =
	(dict: Record<string, string>, locale: string) =>
	(key: MessageKey, params?: Record<string, string | number>) =>
		interpolate(dict[key], params, locale);
const t = tIn(en, 'en');

function svgOf(
	r: YearInRunningRecap,
	unit: 'km' | 'mi',
	periodLabel?: string,
	opts: Parameters<typeof buildRecapShareSvg>[1] = {},
): string {
	return buildRecapShareSvg(recapCardText(r, unit, t, { periodLabel, locale: 'en' }), opts);
}

function recap(over: Partial<YearInRunningRecap> = {}): YearInRunningRecap {
	return {
		year: 2026,
		runCount: 142,
		totalDistanceM: 1_234_000,
		totalDurationS: 3600 * 110,
		totalElevationM: 12345,
		longestRunM: 42195,
		fastestPaceSecPerKm: 270,
		bestStreakDays: 21,
		currentStreakDays: 4,
		earliestStartLocal: '05:30',
		latestStartLocal: '21:10',
		monthly: Array.from({ length: 12 }, (_, i) => ({
			month: i + 1,
			distanceM: i < 9 ? 100000 : 0,
			runCount: i < 9 ? 12 : 0,
			durationS: i < 9 ? 36000 : 0,
		})),
		topWeek: { weekStart: '2026-03-09', distanceM: 95000, runCount: 6 },
		uniqueRouteCount: 18,
		mostUsedActivity: 'run',
		photoCount: 0,
		personalRecordCount: 0,
		parkCourseCount: 0,
		parkCount: 0,
		badges: [],
		...over,
	};
}

test('renders a well-formed svg with the year and headline distance', () => {
	const svg = svgOf(recap(), 'km');
	assert.ok(svg.startsWith('<svg'));
	assert.ok(svg.trimEnd().endsWith('</svg>'));
	assert.ok(svg.includes('viewBox="0 0 1080 1080"'));
	assert.ok(svg.includes('MY 2026 IN RUNNING'));
	assert.ok(svg.includes('1,234 km'));
	assert.ok(svg.includes('across 142 runs'));
});

test('honours the mi unit on every distance field', () => {
	const svg = svgOf(recap(), 'mi');
	assert.ok(svg.includes('767 mi')); // 1_234_000 m / 1609.344
	assert.ok(svg.includes('26 mi')); // 42195 m longest run
	assert.ok(svg.includes('40,502 ft')); // 12345 m climbed
	assert.ok(!svg.includes(' km'));
	assert.ok(!svg.includes(' m<'));
});

test('singularises a single-run year', () => {
	const svg = svgOf(recap({ runCount: 1 }), 'km');
	assert.ok(svg.includes('across 1 run'));
	assert.ok(!svg.includes('across 1 runs'));
});

test('shows active-month count out of twelve', () => {
	const svg = svgOf(recap(), 'km');
	assert.ok(svg.includes('9 / 12'));
});

test('a periodLabel renders a monthly kicker instead of the year', () => {
	const svg = svgOf(recap({ month: 3 }), 'km', 'March 2026');
	assert.ok(svg.includes('MY MARCH 2026 IN RUNNING'));
	assert.ok(!svg.includes('MY 2026 IN RUNNING'));
});

test('escapes nothing dangerous but stays valid with zeroed data', () => {
	const svg = svgOf(
		recap({
			runCount: 0,
			totalDistanceM: 0,
			longestRunM: 0,
			topWeek: null,
			totalElevationM: 0,
			bestStreakDays: 0,
		}),
		'km',
	);
	assert.ok(svg.includes('0 km'));
	assert.ok(svg.includes('across 0 runs'));
	assert.ok(svg.includes('0 days'));
});

test('the square card is the default and draws no footer', () => {
	const svg = svgOf(recap(), 'km');
	assert.equal(svg, svgOf(recap(), 'km', undefined, { aspect: 'square' }));
	assert.doesNotMatch(svg, /<text[^>]*>threkir\.com<\/text>/);
});

test('a story is 1080x1920 with the same stats and the site address', () => {
	const svg = svgOf(recap(), 'km', undefined, { aspect: 'story' });
	assert.ok(svg.includes('viewBox="0 0 1080 1920"'));
	assert.ok(svg.includes('<rect width="1080" height="1920"'));
	assert.ok(svg.includes('MY 2026 IN RUNNING'));
	assert.ok(svg.includes('1,234 km'));
	assert.ok(svg.includes('9 / 12'));
	assert.match(svg, /<text[^>]*>threkir\.com<\/text>/);
});

test('a German reader gets the German card, not the English one', () => {
	const svg = buildRecapShareSvg(recapCardText(recap(), 'km', tIn(de, 'de'), { locale: 'de' }));
	assert.ok(svg.includes('MEIN LAUFJAHR 2026'));
	assert.ok(svg.includes('in 142 Läufen'));
	assert.ok(svg.includes('LÄNGSTER LAUF'));
	assert.ok(svg.includes('21 Tage'));
	assert.ok(svg.includes('12.345 m'));
	assert.ok(!svg.includes('IN RUNNING'));
	assert.ok(!svg.includes('LONGEST RUN'));
});

test('a single-day streak is singular', () => {
	assert.ok(svgOf(recap({ bestStreakDays: 1 }), 'km').includes('>1 day<'));
});
