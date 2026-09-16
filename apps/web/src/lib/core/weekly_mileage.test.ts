import { test } from 'node:test';
import assert from 'node:assert/strict';
import { bucketWeeklyMileage } from './weekly_mileage';

// The chart's window is CONTINUOUS: `maxWeeks` buckets ending with the week
// containing `now`, zero where nothing was run. Every test therefore pins its
// own `now` — built from local calendar components, not an ISO instant, so
// the window lands on the same weeks in the runner's zone and on UTC CI.
//
// The run timestamps stay at 12:00Z, which is the same calendar day in every
// zone this app ships to.

/// Thursday 8 January 2026. Monday-anchored, the window's last bucket is the
/// week of Monday the 5th and its first is the week of Monday 20 October.
const NOW = new Date(2026, 0, 8, 12);

/// Distances by bucket, for asserting the shape of a window in one line.
function distances(bars: { distance_m: number }[]): number[] {
	return bars.map((b) => b.distance_m);
}

test('bucketWeeklyMileage — sums runs in the same Monday-week', () => {
	// 2026-01-05 is a Monday; the 7th is the same week.
	const out = bucketWeeklyMileage(
		[
			{ started_at: '2026-01-05T12:00:00Z', distance_m: 5000 },
			{ started_at: '2026-01-07T12:00:00Z', distance_m: 3000 },
		],
		12,
		'en-GB',
		'monday',
		NOW,
	);
	assert.equal(out.length, 12, 'the window is the last twelve weeks, run or not');
	assert.equal(out[11].distance_m, 8000, 'both runs land in the current week');
	assert.equal(
		distances(out).filter((d) => d > 0).length,
		1,
		'and in no other',
	);
});

test('bucketWeeklyMileage — a week off is a gap, not a closed-up bar', () => {
	// The defect the continuous window closes. These two runs are three weeks
	// apart; the old bucketing emitted two ADJACENT bars, so a fortnight off
	// looked like two consecutive weeks of training.
	const out = bucketWeeklyMileage(
		[
			{ started_at: '2025-12-15T12:00:00Z', distance_m: 20000 },
			{ started_at: '2026-01-05T12:00:00Z', distance_m: 30000 },
		],
		12,
		'en-GB',
		'monday',
		NOW,
	);
	assert.equal(out[11].distance_m, 30000, 'the current week');
	assert.equal(out[8].distance_m, 20000, 'three weeks back');
	assert.deepEqual(
		distances(out).slice(9, 11),
		[0, 0],
		'the two weeks between them are empty buckets, not absent ones',
	);
});

test('bucketWeeklyMileage — does NOT merge the same calendar week across years', () => {
	// The year-merge regression: a day/month-only key fused early-Jan 2025
	// with early-Jan 2026 into one bar. The window now drops the 2025 run as
	// out of range, which is the stronger form of not merging it.
	const out = bucketWeeklyMileage(
		[
			{ started_at: '2025-01-06T12:00:00Z', distance_m: 4000 },
			{ started_at: '2026-01-06T12:00:00Z', distance_m: 6000 },
		],
		12,
		'en-GB',
		'monday',
		NOW,
	);
	assert.equal(
		distances(out).reduce((a, b) => a + b, 0),
		6000,
		"last year's January must not reach this January's bucket",
	);
});

test('bucketWeeklyMileage — the window is exactly maxWeeks, oldest first', () => {
	const runs = Array.from({ length: 20 }, (_, i) => ({
		// One run per week, Mondays stepping forward so the twentieth lands
		// on 2026-01-05 — the window's last bucket.
		started_at: new Date(Date.UTC(2025, 7, 25 + i * 7, 12)).toISOString(),
		distance_m: (i + 1) * 1000,
	}));
	const out = bucketWeeklyMileage(runs, 12, 'en-GB', 'monday', NOW);
	assert.equal(out.length, 12);
	// The last 12 of the 20 weekly runs → 9000…20000, ascending. The eight
	// older ones fall outside the window and are dropped rather than summed
	// into its first bucket.
	assert.deepEqual(distances(out), [
		9000, 10000, 11000, 12000, 13000, 14000, 15000, 16000, 17000, 18000, 19000, 20000,
	]);
});

test('bucketWeeklyMileage — nothing in the window → empty output', () => {
	// Not twelve zero-height bars: the dashboard shows its own "no mileage
	// yet" copy on an empty array, which is what a new account should read.
	assert.deepEqual(bucketWeeklyMileage([], 12, 'en-GB', 'monday', NOW), []);
	assert.deepEqual(
		bucketWeeklyMileage(
			[{ started_at: '2024-05-05T12:00:00Z', distance_m: 9000 }],
			12,
			'en-GB',
			'monday',
			NOW,
		),
		[],
		'a run older than the window is not a chart',
	);
});

test('bucketWeeklyMileage — the week label honours the locale (W-10 label)', () => {
	const runs = [{ started_at: '2026-01-05T12:00:00Z', distance_m: 1000 }];
	const at = (locale: string) =>
		bucketWeeklyMileage(runs, 12, locale, 'monday', NOW)[11].week;
	assert.match(at('en-GB'), /Jan/, 'en short month');
	assert.match(at('ja'), /月/, 'ja uses CJK month marker');
	assert.doesNotMatch(at('ja'), /Jan/);
	assert.notEqual(at('en-GB'), at('de'), 'de differs from en-GB (5. Jan. vs 5 Jan)');
});

test('bucketWeeklyMileage — the week anchor honours week_start_day (W-14)', () => {
	// 2026-01-04 is a Sunday, 2026-01-05 the following Monday.
	const runs = [
		{ started_at: '2026-01-04T12:00:00Z', distance_m: 1000 },
		{ started_at: '2026-01-05T12:00:00Z', distance_m: 2000 },
	];
	// Monday-anchored: the Sunday closes the previous week, so the two runs
	// land in adjacent buckets.
	const mon = bucketWeeklyMileage(runs, 12, 'en', 'monday', NOW);
	assert.deepEqual(distances(mon).slice(10), [1000, 2000]);
	// Sunday-anchored: both fall in the same Sunday-started week.
	const sun = bucketWeeklyMileage(runs, 12, 'en', 'sunday', NOW);
	assert.deepEqual(distances(sun).slice(10), [0, 3000]);
});

test('bucketWeeklyMileage — the bucket KEY stays locale-independent', () => {
	const runs = [
		{ started_at: '2026-01-05T12:00:00Z', distance_m: 1000 },
		{ started_at: '2026-01-07T12:00:00Z', distance_m: 2000 },
	];
	// Same Monday-week regardless of label locale → one merged bucket.
	const out = bucketWeeklyMileage(runs, 12, 'ja', 'monday', NOW);
	assert.equal(out[11].distance_m, 3000);
	assert.equal(
		distances(out).filter((d) => d > 0).length,
		1,
		'a localised label must not split a week in two',
	);
});
