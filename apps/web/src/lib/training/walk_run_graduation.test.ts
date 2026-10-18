import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generatePlan } from './training.ts';
import { structureRunDistanceM, walkRunGraduation, type GraduationWorkout } from './walk_run_graduation.ts';

// Mirrored case-for-case by apps/mobile_android/test/walk_run_graduation_test.dart.

function wo(
	id: string,
	kind: string,
	scheduled_date: string,
	done: boolean,
	runDistanceM: number | null = null
): GraduationWorkout {
	return { id, kind, scheduled_date, done, runDistanceM };
}

test('walkRunGraduation: the 5K done is a graduation', () => {
	const g = walkRunGraduation([
		wo('a', 'walk_run', '2026-03-02', true),
		wo('r', 'rest', '2026-03-03', false),
		wo('b', 'walk_run', '2026-03-06', true, 5000),
		wo('r2', 'rest', '2026-03-07', false)
	]);
	assert.deepEqual(g, { workoutId: 'b', date: '2026-03-06', ranFiveK: true });
});

test('walkRunGraduation: nothing until the last session is done, earlier sessions do not count', () => {
	assert.equal(
		walkRunGraduation([wo('a', 'walk_run', '2026-03-02', true), wo('b', 'walk_run', '2026-03-06', false, 5000)]),
		null
	);
});

test('walkRunGraduation: an older plan ending on a timed run graduates without a 5K', () => {
	const g = walkRunGraduation([wo('a', 'walk_run', '2026-03-02', false), wo('b', 'walk_run', '2026-03-06', true)]);
	assert.deepEqual(g, { workoutId: 'b', date: '2026-03-06', ranFiveK: false });
});

test('walkRunGraduation: never for a plan that is not walk-run', () => {
	assert.equal(
		walkRunGraduation([wo('a', 'walk_run', '2026-03-02', true, 5000), wo('e', 'easy', '2026-03-01', true)]),
		null
	);
	assert.equal(walkRunGraduation([wo('r', 'rest', '2026-03-01', false)]), null);
	assert.equal(walkRunGraduation([]), null);
});

test('walkRunGraduation: the last session is the latest date, not the last row', () => {
	const g = walkRunGraduation([
		wo('late', 'walk_run', '2026-03-06', true, 5000),
		wo('early', 'walk_run', '2026-03-02', false),
		wo('race', 'race', '2026-03-01', false)
	]);
	assert.equal(g?.workoutId, 'late');
});

test('structureRunDistanceM: the run distance, or null for a timed or unreadable structure', () => {
	assert.equal(structureRunDistanceM({ repeats: { count: 1, distance_m: 5000, recovery_pace: 'walk' } }), 5000);
	assert.equal(structureRunDistanceM({ repeats: { count: 1, duration_s: 1800, recovery_pace: 'walk' } }), null);
	assert.equal(structureRunDistanceM({ repeats: { distance_m: '5000' } }), null);
	assert.equal(structureRunDistanceM({ repeats: [] }), null);
	assert.equal(structureRunDistanceM(null), null);
	assert.equal(structureRunDistanceM('x'), null);
});

test("walkRunGraduation: the generator's plan graduates on its final session", () => {
	const plan = generatePlan({ goalEvent: 'distance_5k', startDate: '2026-06-01', daysPerWeek: 3, beginnerWalkRun: true });
	const rows = plan.weeks
		.flatMap((w) => w.workouts)
		.map((w, i) => wo(`w${i}`, w.kind, w.scheduled_date, w.kind === 'walk_run', structureRunDistanceM(w.structure)));
	const g = walkRunGraduation(rows);
	assert.equal(g?.ranFiveK, true);
	assert.equal(g?.date, '2026-07-31');
	assert.equal(walkRunGraduation(rows.map((r) => (r.id === g?.workoutId ? { ...r, done: false } : r))), null);
});
