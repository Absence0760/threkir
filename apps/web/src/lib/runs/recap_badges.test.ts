import { test } from 'node:test';
import assert from 'node:assert/strict';

import { computeRecapBadges } from './recap';

// The year-in-review trophy grid. A badge awarded one unit early, or a tier
// that stacks instead of replacing the lower one, is a visible wrong claim
// on a page people share.

const NONE = {
	totalDistanceM: 0,
	runCount: 0,
	bestStreakDays: 0,
	totalElevationM: 0,
	longestRunM: 0,
	activeMonths: 0,
	distinctActivities: 0,
	earliestStartLocal: null,
	latestStartLocal: null,
	photoCount: 0,
	personalRecordCount: 0,
};

const ids = (over: Partial<typeof NONE>) => computeRecapBadges({ ...NONE, ...over }).map((b) => b.id);

test('an empty year earns nothing', () => {
	assert.deepEqual(computeRecapBadges(NONE), []);
});

test('every threshold is inclusive, and one unit short earns the tier below', () => {
	const cases: Array<[Partial<typeof NONE>, Partial<typeof NONE>, string, string | undefined]> = [
		[{ totalDistanceM: 100000 }, { totalDistanceM: 99999 }, 'dist-100', undefined],
		[{ totalDistanceM: 2000000 }, { totalDistanceM: 1999999 }, 'dist-2000', 'dist-1000'],
		[{ runCount: 50 }, { runCount: 49 }, 'runs-50', undefined],
		[{ longestRunM: 21097 }, { longestRunM: 21096 }, 'long-half', undefined],
		[{ longestRunM: 42195 }, { longestRunM: 42194 }, 'long-marathon', 'long-half'],
		[{ bestStreakDays: 7 }, { bestStreakDays: 6 }, 'streak-7', undefined],
		[{ totalElevationM: 8849 }, { totalElevationM: 8848 }, 'elev-everest', 'elev-5000'],
		[{ activeMonths: 6 }, { activeMonths: 5 }, 'months-6', undefined],
	];
	for (const [at, below, want, wantBelow] of cases) {
		assert.deepEqual(ids(at), [want], JSON.stringify(at));
		assert.deepEqual(ids(below), wantBelow ? [wantBelow] : [], JSON.stringify(below));
	}
});

test('each category awards only its highest tier', () => {
	assert.deepEqual(
		ids({
			totalDistanceM: 2500000,
			runCount: 250,
			longestRunM: 60000,
			bestStreakDays: 40,
			totalElevationM: 20000,
			activeMonths: 12,
			personalRecordCount: 9,
			photoCount: 30,
		}),
		['dist-2000', 'runs-200', 'long-ultra', 'streak-30', 'elev-everest', 'months-12', 'pr-5', 'photo-25'],
	);
});

test('Early bird is strictly before 06:00; Night owl starts at 21:00', () => {
	assert.deepEqual(ids({ earliestStartLocal: '05:59' }), ['early']);
	assert.deepEqual(ids({ earliestStartLocal: '06:00' }), []);
	assert.deepEqual(ids({ latestStartLocal: '21:00' }), ['night']);
	assert.deepEqual(ids({ latestStartLocal: '20:59' }), []);
});

test('All-rounder needs three activity types', () => {
	assert.deepEqual(ids({ distinctActivities: 2 }), []);
	assert.deepEqual(ids({ distinctActivities: 3 }), ['variety']);
});

test('single-item details are singular, and streak details quote the real count', () => {
	const one = computeRecapBadges({ ...NONE, personalRecordCount: 1, photoCount: 1 });
	assert.deepEqual(
		one.map((b) => b.detail),
		['1 personal record', '1 run photo'],
	);
	const two = computeRecapBadges({ ...NONE, personalRecordCount: 2, photoCount: 2, bestStreakDays: 19 });
	assert.deepEqual(
		two.map((b) => b.detail),
		['19 days in a row', '2 personal records', '2 run photos'],
	);
});

test('badge ids are unique across a full grid, so the UI can key on them', () => {
	const all = computeRecapBadges({
		...NONE,
		totalDistanceM: 1e7,
		runCount: 300,
		longestRunM: 1e5,
		bestStreakDays: 60,
		totalElevationM: 1e5,
		activeMonths: 12,
		personalRecordCount: 10,
		photoCount: 50,
		distinctActivities: 5,
		earliestStartLocal: '04:30',
		latestStartLocal: '22:15',
	});
	assert.equal(all.length, 11);
	assert.equal(new Set(all.map((b) => b.id)).size, all.length);
});
