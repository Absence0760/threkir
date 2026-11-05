import { test } from 'node:test';
import assert from 'node:assert/strict';
import { weekAdviceKind, workoutAdviceKind } from './plan_advice.ts';
import { generatePlan } from './training.ts';

const wo = (kind: string) => ({ kind });

test('weekAdviceKind: race, taper and graduation weeks read their phase', () => {
	assert.equal(weekAdviceKind('race', [wo('race')]), 'race');
	assert.equal(weekAdviceKind('taper', [wo('long')]), 'taper');
	assert.equal(weekAdviceKind('graduation', [wo('walk_run')]), 'graduation');
});

test('weekAdviceKind: a walk-run week asks the runner to take the walk breaks', () => {
	assert.equal(
		weekAdviceKind('build', [wo('walk_run'), wo('rest')]),
		'walk_breaks'
	);
});

test('weekAdviceKind: a week holding two long runs is a back-to-back weekend', () => {
	assert.equal(
		weekAdviceKind('build', [wo('long'), wo('easy'), wo('long')]),
		'back_to_back'
	);
	assert.equal(weekAdviceKind('peak', [wo('long'), wo('long')]), 'back_to_back');
});

test('weekAdviceKind: an ordinary build week has no advice', () => {
	assert.equal(weekAdviceKind('build', [wo('long'), wo('easy')]), null);
	assert.equal(weekAdviceKind('base', [wo('easy')]), null);
	assert.equal(weekAdviceKind('peak', []), null);
});

test('workoutAdviceKind: a long run set by time with no pace is time on feet', () => {
	const base = { target_distance_m: 20_000, target_pace_sec_per_km: null };
	assert.equal(workoutAdviceKind({ kind: 'long', ...base, target_duration_seconds: 10_800 }), 'time_on_feet');
	assert.equal(
		workoutAdviceKind({ kind: 'long', ...base, target_duration_seconds: 10_800, target_pace_sec_per_km: 360 }),
		'long'
	);
	assert.equal(workoutAdviceKind({ kind: 'long', ...base, target_duration_seconds: null }), 'long');
});

test('workoutAdviceKind: a race past the marathon is an ultra race', () => {
	const w = { target_duration_seconds: null, target_pace_sec_per_km: null };
	assert.equal(workoutAdviceKind({ kind: 'race', target_distance_m: 50_000, ...w }), 'ultra_race');
	assert.equal(workoutAdviceKind({ kind: 'race', target_distance_m: 42_195, ...w }), 'race');
	assert.equal(workoutAdviceKind({ kind: 'race', target_distance_m: null, ...w }), 'race');
});

test('workoutAdviceKind: the other kinds keep their own advice, recovery reads as easy', () => {
	const w = { target_distance_m: null, target_duration_seconds: null, target_pace_sec_per_km: null };
	assert.equal(workoutAdviceKind({ kind: 'recovery', ...w }), 'easy');
	for (const k of ['easy', 'tempo', 'interval', 'marathon_pace', 'walk_run'] as const) {
		assert.equal(workoutAdviceKind({ kind: k, ...w }), k);
	}
	assert.equal(workoutAdviceKind({ kind: 'rest', ...w }), 'rest');
});

test('generatePlan: an ultra plan reads back-to-back weekends and time-on-feet long runs from its rows', () => {
	const plan = generatePlan({
		goalEvent: 'custom',
		goalDistanceM: 100_000,
		startDate: '2026-11-01',
		daysPerWeek: 5,
		recent5kSec: 1_500
	});
	const kinds = plan.weeks.map((w) => weekAdviceKind(w.phase, w.workouts));
	assert.ok(kinds.includes('back_to_back'));
	assert.equal(kinds.at(-1), 'race');
	const long = plan.weeks.flatMap((w) => w.workouts).find((w) => w.kind === 'long');
	assert.equal(long && workoutAdviceKind(long), 'time_on_feet');
	const race = plan.weeks.flatMap((w) => w.workouts).find((w) => w.kind === 'race');
	assert.equal(race && workoutAdviceKind(race), 'ultra_race');
});
