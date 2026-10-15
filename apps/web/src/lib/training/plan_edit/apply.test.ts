// Unit tests for applying AI plan-edit operations and grading the result.
// Run via `npx tsx --test apps/web/src/lib/training/plan_edit/apply.test.ts`.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { applyPlanEditOps, openWeekBands, planEditLoadCheck, plannedWeekVolumeM } from './apply';
import { TODAY, fixture } from './test_fixture';

const STEADY = { weeklyM: 38_000, activeWeeks: 4 };

test('a move changes only the date, and only of that workout', () => {
	const before = fixture();
	const r = applyPlanEditOps(before, [{ op: 'move_workout', workoutId: 'b-long', date: '2026-10-24' }], TODAY);
	assert.equal(r.applied, 1);
	assert.equal(r.workouts.length, 1);
	assert.deepEqual(r.workouts[0].patch, { scheduled_date: '2026-10-24' });
	assert.equal(r.workouts[0].skip, false);
	assert.equal(r.workouts[0].before.scheduledDate, '2026-10-25');
	assert.equal(r.workouts[0].after.scheduledDate, '2026-10-24');
	assert.deepEqual(r.weeks, []);
	// The input is never mutated.
	assert.equal(before.workouts.find((w) => w.id === 'b-long')!.scheduled_date, '2026-10-25');
});

test('a swap exchanges the two dates', () => {
	const r = applyPlanEditOps(
		fixture(),
		[{ op: 'swap_days', workoutId: 'b-int', otherWorkoutId: 'b-easy2' }],
		TODAY,
	);
	const byId = new Map(r.workouts.map((c) => [c.workoutId, c]));
	assert.equal(byId.get('b-int')!.after.scheduledDate, '2026-10-24');
	assert.equal(byId.get('b-easy2')!.after.scheduledDate, '2026-10-20');
});

test('a recovery week is exactly the manual "make recovery week" patch', () => {
	const r = applyPlanEditOps(fixture(), [{ op: 'mark_recovery', weekIndex: 1 }], TODAY);
	const byId = new Map(r.workouts.map((c) => [c.workoutId, c]));
	assert.deepEqual(byId.get('b-int')!.patch, {
		kind: 'recovery',
		target_distance_m: 4800,
		target_pace_sec_per_km: null,
		target_pace_tolerance_sec: null,
		structure: null,
	});
	assert.deepEqual(byId.get('b-long')!.patch, { target_distance_m: 12_000 });
	assert.equal(byId.has('b-rest'), false);
	assert.deepEqual(r.weeks, [
		{ weekId: 'wk1', weekIndex: 1, beforeVolumeM: 42_000, afterVolumeM: 25_200 },
	]);
});

test('a scaled week scales unstructured sessions and the target, never a structured one', () => {
	const r = applyPlanEditOps(fixture(), [{ op: 'scale_week', weekIndex: 1, factor: 0.8 }], TODAY);
	const byId = new Map(r.workouts.map((c) => [c.workoutId, c]));
	assert.equal(byId.has('b-int'), false);
	assert.deepEqual(byId.get('b-easy')!.patch, { target_distance_m: 6400 });
	assert.deepEqual(byId.get('b-long')!.patch, { target_distance_m: 16_000 });
	assert.equal(r.weeks[0].afterVolumeM, 33_600);
});

test('a scaled current week leaves the sessions already done alone', () => {
	const r = applyPlanEditOps(fixture(), [{ op: 'scale_week', weekIndex: 0, factor: 0.5 }], TODAY);
	const ids = r.workouts.map((c) => c.workoutId).sort();
	assert.deepEqual(ids, ['a-easy', 'a-long', 'a-tempo']);
});

test('a skip carries no field patch and drops the workout from the week\'s load', () => {
	const r = applyPlanEditOps(fixture(), [{ op: 'skip_workout', workoutId: 'c-easy' }], TODAY);
	assert.deepEqual(r.workouts.map((c) => [c.workoutId, c.patch, c.skip]), [['c-easy', null, true]]);
	assert.equal(plannedWeekVolumeM(r.after, 'wk2'), 34_000);
});

test('an operation whose target stopped being editable is not applied', () => {
	const snapshot = fixture();
	snapshot.workouts.find((w) => w.id === 'b-long')!.completed_run_id = 'run-1';
	const r = applyPlanEditOps(snapshot, [{ op: 'move_workout', workoutId: 'b-long', date: '2026-10-24' }], TODAY);
	assert.equal(r.applied, 0);
	assert.deepEqual(r.workouts, []);
});

test('week load is the sum of workout distances, or the target when none carries one', () => {
	const snapshot = fixture();
	assert.equal(plannedWeekVolumeM(snapshot, 'wk1'), 42_000);
	for (const w of snapshot.workouts) if (w.week_id === 'wk3') w.target_distance_m = null;
	assert.equal(plannedWeekVolumeM(snapshot, 'wk3'), 30_000);
});

test('each open week is banded against the four before it, the runner\'s recent volume filling the start', () => {
	const bands = openWeekBands(fixture(), STEADY, TODAY);
	assert.deepEqual([...bands.entries()], [
		[0, 'optimal'],
		[1, 'optimal'],
		[2, 'optimal'],
		[3, 'low'],
	]);
	// Too little history to stand behind: the pre-plan slots are left out.
	const thin = openWeekBands(fixture(), { weeklyM: 1000, activeWeeks: 1 }, TODAY);
	assert.equal(thin.get(0), 'insufficient');
});

test('an edit that keeps every band and stacks nothing is ok', () => {
	const before = fixture();
	const { after } = applyPlanEditOps(before, [{ op: 'move_workout', workoutId: 'b-long', date: '2026-10-24' }], TODAY);
	assert.deepEqual(planEditLoadCheck(before, after, STEADY, TODAY), {
		verdict: 'ok',
		raisedWeeks: [],
		stackedDays: [],
	});
});

test('making a week easier is ok', () => {
	const before = fixture();
	const { after } = applyPlanEditOps(before, [{ op: 'scale_week', weekIndex: 1, factor: 0.8 }], TODAY);
	assert.equal(planEditLoadCheck(before, after, STEADY, TODAY).verdict, 'ok');
});

test('a week pushed into the elevated band needs a second confirmation', () => {
	const before = fixture();
	const recent = { weeklyM: 30_000, activeWeeks: 4 };
	const { after } = applyPlanEditOps(before, [{ op: 'scale_week', weekIndex: 1, factor: 1.1 }], TODAY);
	const check = planEditLoadCheck(before, after, recent, TODAY);
	assert.equal(check.verdict, 'confirm');
	assert.deepEqual(check.raisedWeeks, [{ weekIndex: 1, before: 'optimal', after: 'elevated' }]);
});

test('a week pushed into the high band rejects the whole set', () => {
	const before = fixture();
	const recent = { weeklyM: 26_000, activeWeeks: 4 };
	const { after } = applyPlanEditOps(
		before,
		[
			{ op: 'scale_week', weekIndex: 1, factor: 1.1 },
			{ op: 'move_workout', workoutId: 'c-long', date: '2026-10-31' },
		],
		TODAY,
	);
	const check = planEditLoadCheck(before, after, recent, TODAY);
	assert.equal(check.verdict, 'reject');
	assert.deepEqual(check.raisedWeeks, [{ weekIndex: 1, before: 'elevated', after: 'high' }]);
});

test('a band the original plan already carried is not blamed on the edit', () => {
	const before = fixture();
	const recent = { weeklyM: 26_000, activeWeeks: 4 };
	// Week 1 is already high against this base (40 km / 26 km).
	const { after } = applyPlanEditOps(before, [{ op: 'skip_workout', workoutId: 'c-easy' }], TODAY);
	assert.equal(planEditLoadCheck(before, after, recent, TODAY).verdict, 'ok');
});

test('two hard sessions newly on adjacent days need a second confirmation', () => {
	const before = fixture();
	const { after } = applyPlanEditOps(
		before,
		[{ op: 'swap_days', workoutId: 'b-int', otherWorkoutId: 'b-easy2' }],
		TODAY,
	);
	const check = planEditLoadCheck(before, after, STEADY, TODAY);
	assert.equal(check.verdict, 'confirm');
	assert.deepEqual(check.stackedDays, [['2026-10-24', '2026-10-25']]);
	assert.deepEqual(check.raisedWeeks, []);
});

test('hard sessions the plan already had back to back are not reported', () => {
	// Saturday tempo + Sunday long run in week 1 come from the plan itself.
	const before = fixture();
	const { after } = applyPlanEditOps(before, [{ op: 'skip_workout', workoutId: 'b-easy' }], TODAY);
	assert.deepEqual(planEditLoadCheck(before, after, STEADY, TODAY).stackedDays, []);
});

test('skipping one of a stacked pair never reports it', () => {
	const before = fixture();
	before.workouts.find((w) => w.id === 'b-easy2')!.kind = 'tempo';
	const { after } = applyPlanEditOps(before, [{ op: 'skip_workout', workoutId: 'b-easy2' }], TODAY);
	assert.deepEqual(planEditLoadCheck(before, after, STEADY, TODAY).stackedDays, []);
});

test('a set mixing every operation kind applies each one, and an easier plan is ok', () => {
	const before = fixture();
	const r = applyPlanEditOps(
		before,
		[
			{ op: 'skip_workout', workoutId: 'a-tempo' },
			{ op: 'move_workout', workoutId: 'b-long', date: '2026-10-24' },
			{ op: 'swap_days', workoutId: 'c-tempo', otherWorkoutId: 'c-easy' },
			{ op: 'mark_recovery', weekIndex: 2 },
			{ op: 'scale_week', weekIndex: 3, factor: 0.9 },
		],
		TODAY,
	);
	assert.equal(r.applied, 5);
	assert.deepEqual(
		r.workouts.map((c) => [c.workoutId, c.patch, c.skip]),
		[
			['a-tempo', null, true],
			['b-long', { scheduled_date: '2026-10-24' }, false],
			[
				'c-tempo',
				{
					scheduled_date: '2026-10-29',
					kind: 'recovery',
					target_distance_m: 6000,
					target_pace_sec_per_km: null,
					target_pace_tolerance_sec: null,
				},
				false,
			],
			['c-easy', { scheduled_date: '2026-10-27', target_distance_m: 6000 }, false],
			['c-long', { target_distance_m: 14_400 }, false],
			['d-easy', { target_distance_m: 7200 }, false],
			['d-tempo', { target_distance_m: 5400 }, false],
		],
	);
	assert.deepEqual(r.weeks, [
		{ weekId: 'wk2', weekIndex: 2, beforeVolumeM: 44_000, afterVolumeM: 26_400 },
		{ weekId: 'wk3', weekIndex: 3, beforeVolumeM: 30_000, afterVolumeM: 27_000 },
	]);
	assert.deepEqual(planEditLoadCheck(before, r.after, STEADY, TODAY), {
		verdict: 'ok',
		raisedWeeks: [],
		stackedDays: [],
	});
});
