import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	FADE_SECONDS,
	MAX_BADGES,
	MAX_MIDDLE_SLIDES,
	recapSlides,
	SLIDE_SECONDS,
	slideshowFrame,
	slideshowTimeline,
	type RecapSlide,
	type RecapSlideFormat,
} from './recap_slideshow';
import type { YearInRunningRecap } from '../runs/recap';
import { en } from '../i18n/locales/en';
import { interpolate } from '../i18n/interpolate';
import type { MessageKey } from '../i18n/messages';

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

const fmt: RecapSlideFormat = {
	t: (key: MessageKey, params?: Record<string, string | number>) => interpolate(en[key], params, 'en'),
	kicker: 'My 2026 in running',
	distance: (m) => `${(m / 1000).toFixed(1)} km`,
	pace: (s) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}/km`,
	weekOf: (iso) => `wk ${iso}`,
	monthName: (mo) => MONTHS[mo - 1],
	monthLetter: (mo) => MONTHS[mo - 1][0],
	count: (n) => n.toLocaleString('en'),
	unit: 'km',
	locale: 'en',
	url: 'threkir.com',
};

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
			distanceM: i < 9 ? 100000 + (i === 2 ? 50000 : 0) : 0,
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

const kinds = (s: RecapSlide[]) => s.map((x) => x.kind);

test('a year opens on the headline, ends on the Threkir card, and reads the page strings', () => {
	const s = recapSlides(recap(), fmt);
	assert.deepEqual(s[0], { kind: 'title', kicker: 'My 2026 in running', hero: '1234.0 km', subhead: 'across 142 runs' });
	assert.deepEqual(s.at(-1), { kind: 'end', line: 'My 2026 in running', url: 'threkir.com' });
	assert.deepEqual(s[1], { kind: 'stat', label: 'Longest run', value: '42.2 km', sub: 'single outing' });
	assert.deepEqual(kinds(s), ['title', 'stat', 'months', 'stat', 'stat', 'stat', 'stat', 'end']);
});

test('the biggest month is named and its bar is the full-height peak', () => {
	const months = recapSlides(recap(), fmt).find((x) => x.kind === 'months');
	assert.ok(months && months.kind === 'months');
	assert.equal(months.value, 'March');
	assert.equal(months.sub, '150.0 km');
	assert.equal(months.bars.length, 12);
	assert.deepEqual(
		months.bars.filter((b) => b.peak).map((b) => [b.month, b.frac]),
		[[3, 1]],
	);
	assert.equal(months.bars[11].frac, 0);
	assert.equal(months.bars[0].letter, 'J');
});

test('a monthly recap has no month chart, and neither does a one-month year', () => {
	assert.ok(!kinds(recapSlides(recap({ month: 3 }), fmt)).includes('months'));
	const oneMonth = recap({
		monthly: Array.from({ length: 12 }, (_, i) => ({ month: i + 1, distanceM: i === 0 ? 5000 : 0, runCount: i === 0 ? 1 : 0, durationS: 0 })),
	});
	assert.ok(!kinds(recapSlides(oneMonth, fmt)).includes('months'));
});

test('a stat with nothing to show earns no slide', () => {
	const s = recapSlides(
		recap({
			month: 3,
			longestRunM: 0,
			topWeek: null,
			fastestPaceSecPerKm: null,
			bestStreakDays: 1,
			totalElevationM: 0.4,
			runCount: 1,
		}),
		fmt,
	);
	assert.deepEqual(kinds(s), ['title', 'end']);
	assert.equal((s[0] as { subhead: string }).subhead, 'across 1 run');
});

test('a rich year is capped to a story-length reel, badges trimmed to the first few', () => {
	const badges = (['dist-100', 'runs-50', 'long-half', 'elev-5000', 'months-12', 'variety', 'night'] as const).map(
		(id) => ({ id, icon: 'star', value: id === 'variety' ? 3 : id === 'night' ? '22:10' : undefined }),
	);
	const s = recapSlides(recap({ personalRecordCount: 3, badges }), fmt);
	assert.equal(s.length, MAX_MIDDLE_SLIDES + 2);
	const few = recapSlides(recap({ month: 3, topWeek: null, fastestPaceSecPerKm: null, badges }), fmt);
	const b = few.find((x) => x.kind === 'badges');
	assert.ok(b && b.kind === 'badges');
	assert.equal(b.items.length, MAX_BADGES);
	assert.equal(b.items[0], 'Century');
	assert.equal(b.sub, '7 earned in 2026');
});

test('a badge that names a distance names it in the reader\'s unit', () => {
	const badges = [{ id: 'dist-1000' as const, icon: 'public' }];
	const km = recapSlides(recap({ month: 3, badges }), fmt).find((x) => x.kind === 'badges');
	const mi = recapSlides(recap({ month: 3, badges }), { ...fmt, unit: 'mi' }).find((x) => x.kind === 'badges');
	assert.ok(km && km.kind === 'badges' && mi && mi.kind === 'badges');
	assert.deepEqual(km.items, ['1,000 km club']);
	assert.deepEqual(mi.items, ['621 mi club']);
});

test('the streak, climb and records slides use the page formatters and plurals', () => {
	const s = recapSlides(recap({ month: 3, personalRecordCount: 2, topWeek: null, fastestPaceSecPerKm: null }), fmt);
	const values = s.filter((x) => x.kind === 'stat').map((x) => (x as { value: string }).value);
	assert.deepEqual(values, ['42.2 km', '21 days', '12,345 m', '2']);
	const mi = recapSlides(recap({ month: 3, personalRecordCount: 2, topWeek: null, fastestPaceSecPerKm: null }), { ...fmt, unit: 'mi' });
	assert.ok(mi.some((x) => x.kind === 'stat' && (x as { value: string }).value === '40,502 ft'));
});

test('the timeline gives each kind its seconds and runs end to end with no gaps', () => {
	const slides = recapSlides(recap(), fmt);
	const tl = slideshowTimeline(slides, 30);
	assert.equal(tl.frames[0], SLIDE_SECONDS.title * 30);
	assert.equal(tl.frames[2], SLIDE_SECONDS.months * 30);
	assert.equal(tl.totalFrames, tl.frames.reduce((a, b) => a + b, 0));
	for (let i = 1; i < slides.length; i++) assert.equal(tl.starts[i], tl.starts[i - 1] + tl.frames[i - 1]);
	assert.equal(tl.totalFrames, 30 * (3 + 2.5 * 5 + 3.5 + 3));
});

test('each frame belongs to one slide, fades in at its start, and the index is clamped', () => {
	const tl = slideshowTimeline(recapSlides(recap(), fmt), 30);
	assert.deepEqual(slideshowFrame(tl, 0), { slide: 0, progress: 0, enter: 1 });
	const s1 = tl.starts[1];
	assert.deepEqual(slideshowFrame(tl, s1), { slide: 1, progress: 0, enter: 0 });
	assert.equal(slideshowFrame(tl, s1 + FADE_SECONDS * 30).enter, 1);
	assert.ok(slideshowFrame(tl, s1 + 6).enter > 0 && slideshowFrame(tl, s1 + 6).enter < 1);
	assert.equal(slideshowFrame(tl, s1 - 1).slide, 0);
	assert.equal(slideshowFrame(tl, s1 - 1).progress, 1);
	const last = slideshowFrame(tl, tl.totalFrames - 1);
	assert.deepEqual(slideshowFrame(tl, tl.totalFrames + 99), last);
	assert.equal(last.slide, tl.starts.length - 1);
	assert.equal(last.progress, 1);
});
