import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	MISSED_PROMPT_WINDOW_DAYS,
	missedWorkoutPrompt,
	type MissedPromptWeek,
	type MissedPromptWorkout
} from './plan_missed_prompt';

// Mirrored case-for-case by apps/mobile_android/test/plan_missed_prompt_test.dart.
const TODAY = '2026-03-11';

function wo(
	id: string,
	scheduledDate: string,
	kind: string,
	targetDistanceM: number | null,
	extra: Partial<MissedPromptWorkout> = {}
): MissedPromptWorkout {
	return { id, scheduledDate, kind, targetDistanceM, completed: false, skipped: false, answered: false, ...extra };
}

function week(
	weekIndex: number,
	phase: string,
	plannedMetres: number,
	workouts: MissedPromptWorkout[]
): MissedPromptWeek {
	return { weekIndex, phase, plannedMetres, workouts };
}

/// A build block: last week's long run on Sunday the 8th, this week's on
/// Sunday the 15th, next week's on the 22nd.
function block(overrides: { lastLong?: Partial<MissedPromptWorkout>; nextPhase?: string; nextPlanned?: number } = {}) {
	return [
		week(0, 'build', 40000, [
			wo('mon', '2026-03-02', 'easy', 8000),
			wo('long-8', '2026-03-08', 'long', 20000, overrides.lastLong ?? {})
		]),
		week(1, 'build', 42000, [
			wo('tue', '2026-03-10', 'tempo', 9000),
			wo('long-15', '2026-03-15', 'long', 18000)
		]),
		week(2, overrides.nextPhase ?? 'build', overrides.nextPlanned ?? 44000, [
			wo('long-22', '2026-03-22', 'long', 19000)
		])
	];
}

test('the window is seven days', () => {
	assert.equal(MISSED_PROMPT_WINDOW_DAYS, 7);
});

test('nothing missed asks nothing', () => {
	const weeks = [week(0, 'build', 20000, [wo('a', '2026-03-10', 'easy', 5000, { completed: true })])];
	assert.equal(missedWorkoutPrompt({ weeks, today: TODAY }), null);
});

test("today's workout is never missed", () => {
	const weeks = [week(0, 'build', 20000, [wo('a', TODAY, 'long', 15000)])];
	assert.equal(missedWorkoutPrompt({ weeks, today: TODAY }), null);
});

test('rest, done and skipped workouts are never asked about', () => {
	const weeks = [
		week(0, 'build', 20000, [
			wo('rest', '2026-03-09', 'rest', null),
			wo('done', '2026-03-08', 'easy', 5000, { completed: true }),
			wo('skip', '2026-03-10', 'tempo', 7000, { skipped: true })
		])
	];
	assert.equal(missedWorkoutPrompt({ weeks, today: TODAY }), null);
});

test('the most recent miss is asked about', () => {
	const p = missedWorkoutPrompt({ weeks: block(), today: TODAY });
	assert.equal(p?.workoutId, 'tue');
	assert.equal(p?.scheduledDate, '2026-03-10');
});

test('an answered miss is not asked again, and the next most recent is', () => {
	const weeks = block();
	weeks[1].workouts[0].answered = true;
	const p = missedWorkoutPrompt({ weeks, today: TODAY });
	assert.equal(p?.workoutId, 'long-8');
});

test('a miss exactly seven days back is asked about, one eight days back is not', () => {
	const seven = [week(0, 'build', 20000, [wo('a', '2026-03-04', 'easy', 5000)])];
	assert.equal(missedWorkoutPrompt({ weeks: seven, today: TODAY })?.workoutId, 'a');
	const eight = [week(0, 'build', 20000, [wo('a', '2026-03-03', 'easy', 5000)])];
	assert.equal(missedWorkoutPrompt({ weeks: eight, today: TODAY }), null);
});

test('two misses on one day keep the earlier in plan order', () => {
	const weeks = [
		week(0, 'build', 20000, [wo('first', '2026-03-10', 'easy', 5000), wo('second', '2026-03-10', 'tempo', 6000)])
	];
	assert.equal(missedWorkoutPrompt({ weeks, today: TODAY })?.workoutId, 'first');
});

test('a missed easy run is let go, with no make-up', () => {
	const weeks = [week(0, 'build', 20000, [wo('a', '2026-03-10', 'easy', 5000), wo('l', '2026-03-15', 'long', 15000)])];
	const p = missedWorkoutPrompt({ weeks, today: TODAY });
	assert.deepEqual(p?.advice, { recommendation: 'skip', reason: 'not_long_run' });
	assert.equal(p?.makeUp, null);
	assert.deepEqual(p?.makeUpAnswers, []);
});

test('a missed tempo is dropped, not moved', () => {
	const p = missedWorkoutPrompt({ weeks: block(), today: TODAY });
	assert.equal(p?.kind, 'tempo');
	assert.deepEqual(p?.advice, { recommendation: 'skip', reason: 'not_long_run' });
	assert.equal(p?.makeUp, null);
});

test('a missed long run in the build is made up by stretching the next long run at most 15%', () => {
	const weeks = block();
	weeks[1].workouts[0].completed = true;
	const p = missedWorkoutPrompt({ weeks, today: TODAY });
	assert.equal(p?.workoutId, 'long-8');
	assert.deepEqual(p?.advice, { recommendation: 'make_up', reason: 'key_session' });
	assert.equal(p?.makeUp?.workoutId, 'long-15');
	assert.equal(p?.makeUp?.fromMetres, 18000);
	assert.equal(p?.makeUp?.toMetres, 20000);
	assert.deepEqual(p?.makeUpAnswers, ['long-8']);
});

test('the stretch is capped at 15% of the next long run', () => {
	const weeks = block({ lastLong: { targetDistanceM: 30000 } });
	weeks[1].workouts[0].completed = true;
	const p = missedWorkoutPrompt({ weeks, today: TODAY });
	assert.equal(p?.makeUp?.toMetres, 20700);
});

test('a missed long run in the taper is let go', () => {
	const weeks = [
		week(0, 'taper', 20000, [wo('long', '2026-03-08', 'long', 16000)]),
		week(1, 'race', 15000, [wo('race', '2026-03-15', 'race', 21097)])
	];
	const p = missedWorkoutPrompt({ weeks, today: TODAY });
	assert.deepEqual(p?.advice, { recommendation: 'skip', reason: 'taper' });
	assert.equal(p?.makeUp, null);
});

test('a missed long run before a recovery week is let go', () => {
	const weeks = block({ nextPlanned: 30000 });
	weeks[0].workouts = [];
	weeks[1].workouts = [wo('long-10', '2026-03-10', 'long', 20000)];
	const p = missedWorkoutPrompt({ weeks, today: TODAY });
	assert.deepEqual(p?.advice, { recommendation: 'skip', reason: 'recovery_soon' });
	assert.equal(p?.makeUp, null);
});

test('a long run the next long run already covers asks with no make-up', () => {
	const weeks = block({ lastLong: { targetDistanceM: 16000 } });
	weeks[1].workouts[0].completed = true;
	const p = missedWorkoutPrompt({ weeks, today: TODAY });
	assert.deepEqual(p?.advice, { recommendation: 'make_up', reason: 'key_session' });
	assert.equal(p?.makeUp, null);
	assert.deepEqual(p?.makeUpAnswers, []);
});

test('an answered long run does not feed the make-up', () => {
	const weeks = [
		week(0, 'build', 40000, [wo('old', '2026-03-01', 'long', 30000, { answered: true })]),
		week(1, 'build', 42000, [wo('new', '2026-03-08', 'long', 19000)]),
		week(2, 'build', 44000, [wo('next', '2026-03-15', 'long', 18000)])
	];
	const p = missedWorkoutPrompt({ weeks, today: TODAY });
	assert.equal(p?.workoutId, 'new');
	assert.equal(p?.makeUp?.toMetres, 19000);
	assert.deepEqual(p?.makeUpAnswers, ['new']);
});

test('an older unanswered missed long run is answered with the make-up it feeds', () => {
	const weeks = [
		week(0, 'build', 40000, [wo('old', '2026-02-22', 'long', 22000)]),
		week(1, 'build', 42000, [wo('new', '2026-03-08', 'long', 19000)]),
		week(2, 'build', 44000, [wo('next', '2026-03-15', 'long', 18000)])
	];
	const p = missedWorkoutPrompt({ weeks, today: TODAY });
	assert.equal(p?.workoutId, 'new');
	assert.equal(p?.makeUp?.toMetres, 20700);
	assert.deepEqual(p?.makeUpAnswers, ['old', 'new']);
});
