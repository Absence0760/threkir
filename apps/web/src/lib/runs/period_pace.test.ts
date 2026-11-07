import { test } from 'node:test';
import assert from 'node:assert/strict';
import { periodPaceTotals } from './period_pace';

test('a run past the ten-day bound is out of both halves of the pace', () => {
	const t = periodPaceTotals([
		{ distance_m: 10_000, duration_s: 3000, activity_type: 'run' },
		{ distance_m: 2000, duration_s: 44_400_094, activity_type: 'run' },
	]);
	assert.deepEqual(t, { distanceM: 10_000, durationS: 3000 });
	assert.equal(t.durationS / (t.distanceM / 1000), 300);
});

test('a ride is left out of the pace', () => {
	assert.deepEqual(
		periodPaceTotals([
			{ distance_m: 5000, duration_s: 1500, activity_type: 'run' },
			{ distance_m: 40_000, duration_s: 4800, activity_type: 'cycle' },
		]),
		{ distanceM: 5000, durationS: 1500 },
	);
});
