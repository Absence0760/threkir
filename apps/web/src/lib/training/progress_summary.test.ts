import { test } from 'node:test';
import assert from 'node:assert/strict';
import { progressSummary } from './progress_summary.ts';
import { weekLead } from './week_lead.ts';

// Wednesday 2026-11-11, local time.
const now = new Date(2026, 10, 11, 18, 0);
const at = (y: number, mo: number, d: number) => new Date(y, mo, d, 7, 0).toISOString();
const activities = [
	{ started_at: at(2026, 10, 11), distance_m: 5_000 },
	{ started_at: at(2026, 10, 9), distance_m: 8_000 }, // Monday this week
	{ started_at: at(2026, 10, 8), distance_m: 10_000 }, // Sunday
	{ started_at: at(2026, 10, 1), distance_m: 3_000 }, // first of the month
	{ started_at: at(2026, 9, 31), distance_m: 20_000 }, // last month
];

test('the month sums from the first of the calendar month', () => {
	assert.equal(progressSummary({ activities, weekStart: 'monday', now }).monthM, 26_000);
});

test("the week is the week lead's figure, for either week start", () => {
	for (const weekStart of ['monday', 'sunday'] as const) {
		const lead = weekLead({ activities, planWorkouts: null, weekStart, now });
		assert.equal(progressSummary({ activities, weekStart, now }).weekM, lead.distanceM);
	}
	assert.equal(progressSummary({ activities, weekStart: 'monday', now }).weekM, 13_000);
	assert.equal(progressSummary({ activities, weekStart: 'sunday', now }).weekM, 23_000);
});

test('no activity is zero, not missing', () => {
	assert.deepEqual(progressSummary({ activities: [], weekStart: 'monday', now }), { weekM: 0, monthM: 0 });
});
