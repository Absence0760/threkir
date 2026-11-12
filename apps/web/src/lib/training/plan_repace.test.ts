import { test } from 'node:test';
import assert from 'node:assert/strict';
import { goalTimeRepacePatches, scaleStructurePaces, type RepaceWorkout } from './plan_repace.ts';
import { resolveTrainingPaces } from './training.ts';

const HALF = 21097.5;

function wo(id: string, date: string, over: Partial<RepaceWorkout> = {}): RepaceWorkout {
	return {
		id,
		scheduled_date: date,
		kind: 'easy',
		target_pace_sec_per_km: 330,
		target_duration_seconds: null,
		structure: null,
		...over
	};
}

const base = {
	goalDistanceM: HALF,
	oldGoalTimeSec: 2 * 3600,
	newGoalTimeSec: 1 * 3600 + 48 * 60,
	recent5kSec: null,
	todayIso: '2026-06-10'
};

test('a faster goal scales every future open pace by the goal-pace ratio', () => {
	const [p] = goalTimeRepacePatches({ ...base, workouts: [wo('a', '2026-06-12')] });
	assert.equal(p.target_pace_sec_per_km, Math.round(330 * (108 / 120)));
});

test('the scaled paces are the ones a fresh plan at the new goal would carry', () => {
	const before = resolveTrainingPaces({ goalDistanceM: HALF, goalTimeSec: base.oldGoalTimeSec });
	const after = resolveTrainingPaces({ goalDistanceM: HALF, goalTimeSec: base.newGoalTimeSec });
	const [p] = goalTimeRepacePatches({
		...base,
		workouts: [wo('t', '2026-06-12', { kind: 'tempo', target_pace_sec_per_km: before.tempo })]
	});
	assert.ok(Math.abs(p.target_pace_sec_per_km! - after.tempo) <= 1, `${p.target_pace_sec_per_km} vs ${after.tempo}`);
});

test('the past, completed and skipped sessions are left alone', () => {
	const patches = goalTimeRepacePatches({
		...base,
		workouts: [
			wo('past', '2026-06-09'),
			wo('done', '2026-06-12', { completed_run_id: 'r1' }),
			wo('manual', '2026-06-12', { manually_completed: true }),
			wo('skipped', '2026-06-12', { skipped_at: '2026-06-12T08:00:00Z' }),
			wo('today', '2026-06-10')
		]
	});
	assert.deepEqual(patches.map((p) => p.id), ['today']);
});

test('a plan anchored on a recent 5K keeps its paces', () => {
	const patches = goalTimeRepacePatches({ ...base, recent5kSec: 1500, workouts: [wo('a', '2026-06-12')] });
	assert.deepEqual(patches, []);
});

test('an unchanged goal changes nothing', () => {
	assert.deepEqual(goalTimeRepacePatches({ ...base, newGoalTimeSec: base.oldGoalTimeSec, workouts: [wo('a', '2026-06-12')] }), []);
});

test('interval and steady paces inside the structure scale; effort labels do not', () => {
	const structure = {
		warmup: { distance_m: 1500, pace: 'easy' },
		repeats: { count: 5, distance_m: 1000, pace_sec_per_km: 240, recovery_distance_m: 400, recovery_pace: 'jog' },
		cooldown: { distance_m: 1500, pace: 'easy' }
	};
	const [p] = goalTimeRepacePatches({
		...base,
		workouts: [wo('i', '2026-06-12', { kind: 'interval', target_pace_sec_per_km: 240, structure })]
	});
	const s = p.structure as typeof structure;
	assert.equal(s.repeats.pace_sec_per_km, Math.round(240 * 0.9));
	assert.equal(s.repeats.recovery_pace, 'jog');
	assert.equal(s.warmup.pace, 'easy');
	assert.equal(s.repeats.distance_m, 1000);
	assert.equal(structure.repeats.pace_sec_per_km, 240, 'the input is not mutated');
});

test('the goal race takes the new goal time; another race keeps its own', () => {
	const patches = goalTimeRepacePatches({
		...base,
		workouts: [
			wo('a-race', '2026-07-01', { kind: 'race', target_pace_sec_per_km: null, target_duration_seconds: 7200 }),
			wo('b-race', '2026-06-20', { kind: 'race', target_pace_sec_per_km: null, target_duration_seconds: 2700 })
		]
	});
	assert.deepEqual(patches, [{ id: 'a-race', target_duration_seconds: 6480 }]);
});

test('a walk-run session with no pace target has nothing to change', () => {
	assert.deepEqual(
		goalTimeRepacePatches({ ...base, workouts: [wo('w', '2026-06-12', { kind: 'walk_run', target_pace_sec_per_km: null })] }),
		[]
	);
});

test('scaleStructurePaces passes scalars and null through', () => {
	assert.equal(scaleStructurePaces(null, 0.9), null);
	assert.equal(scaleStructurePaces('easy', 0.9), 'easy');
	assert.deepEqual(scaleStructurePaces({ steady: { pace_sec_per_km: 300 } }, 0.9), { steady: { pace_sec_per_km: 270 } });
});
