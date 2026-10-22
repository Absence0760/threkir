// Unit tests for applying AI plan-edit operations and grading the result.
// Run via `npx tsx --test apps/web/src/lib/training/plan_edit/apply.test.ts`.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { applyPlanEditOps, openWeekBands, planEditLoadCheck, plannedWeekVolumeM } from './apply';
import { TODAY, fixture } from './test_fixture';

const STEADY = { weeklyM: 38_000, activeWeeks: 4 };

test('a move onto an empty day changes only the date, and only of that workout', () => {
	const before = fixture();
	const r = applyPlanEditOps(before, [{ op: 'move_workout', workoutId: 'b-long', date: '2026-10-21' }], TODAY);
	assert.equal(r.applied, 1);
	assert.equal(r.workouts.length, 1);
	assert.deepEqual(r.workouts[0].patch, { scheduled_date: '2026-10-21' });
	assert.equal(r.workouts[0].skip, false);
	assert.equal(r.workouts[0].before.scheduledDate, '2026-10-25');
	assert.equal(r.workouts[0].after.scheduledDate, '2026-10-21');
	assert.deepEqual(r.weeks, []);
	// The input is never mutated.
	assert.equal(before.workouts.find((w) => w.id === 'b-long')!.scheduled_date, '2026-10-25');
});

test('a move onto an occupied day trades days with the occupant, rest days included', () => {
	const r = applyPlanEditOps(fixture(), [{ op: 'move_workout', workoutId: 'b-easy', date: '2026-10-23' }], TODAY);
	assert.equal(r.applied, 1);
	assert.deepEqual(
		r.workouts.map((c) => [c.workoutId, c.patch]),
		[
			['b-easy', { scheduled_date: '2026-10-23' }],
			['b-rest', { scheduled_date: '2026-10-22' }],
		],
	);
	const dates = r.after.workouts.filter((w) => w.week_id === 'wk1').map((w) => w.scheduled_date);
	assert.equal(new Set(dates).size, dates.length, 'still one row per day');
});

test('a move onto a race day or a completed workout is dropped', () => {
	const before = fixture();
	before.workouts.find((w) => w.id === 'b-easy2')!.manually_completed = true;
	const r = applyPlanEditOps(
		before,
		[
			{ op: 'move_workout', workoutId: 'd-tempo', date: '2026-11-08' },
			{ op: 'move_workout', workoutId: 'b-long', date: '2026-10-24' },
		],
		TODAY,
	);
	assert.equal(r.applied, 0);
	assert.deepEqual(r.workouts, []);
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
			['b-easy2', { scheduled_date: '2026-10-25' }, false],
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

test('a scale-up leaves a B/C race window and a taper-eased workout alone; a scale-down does not', () => {
	// A C race on Monday 2026-11-02: its 3-day taper reaches back to Friday
	// 10-30, so week 3's Sunday long run (11-01) is inside it and the Tuesday
	// tempo and Thursday easy run are not (race_taper.ts, decisions § 2051).
	const base = fixture();
	base.workouts.push({
		id: 'c-race',
		week_id: 'wk3',
		scheduled_date: '2026-11-02',
		kind: 'race',
		target_distance_m: 10_000,
		race_priority: 'C',
	});
	const up = applyPlanEditOps(base, [{ op: 'scale_week', weekIndex: 2, factor: 1.1 }], TODAY);
	const after = (id: string) => up.after.workouts.find((w) => w.id === id)!.target_distance_m;
	assert.equal(after('c-tempo'), 11_000);
	assert.equal(after('c-easy'), 11_000);
	assert.equal(after('c-long'), 24_000, 'inside the C race taper: not scaled up');
	// The target rises by what the scaled sessions add, not by the held 24 km's share.
	assert.equal(up.weeks.find((w) => w.weekId === 'wk2')!.afterVolumeM, 46_000);

	const eased = fixture();
	eased.workouts.find((w) => w.id === 'c-easy')!.race_taper_applied_at = '2026-10-10T00:00:00Z';
	const up2 = applyPlanEditOps(eased, [{ op: 'scale_week', weekIndex: 2, factor: 1.1 }], TODAY);
	assert.equal(up2.after.workouts.find((w) => w.id === 'c-easy')!.target_distance_m, 10_000);

	const down = applyPlanEditOps(base, [{ op: 'scale_week', weekIndex: 2, factor: 0.9 }], TODAY);
	assert.equal(down.after.workouts.find((w) => w.id === 'c-long')!.target_distance_m, 21_600);
});

test('a workout moved into a B/C race window is held at its targets whatever order the operations come in', () => {
	// Thursday's easy run (10-29) is four days before a C race on 11-02, outside
	// its 3-day taper; moved to Friday 10-30 it is inside.
	const base = fixture();
	base.workouts.push({
		id: 'c-race',
		week_id: 'wk3',
		scheduled_date: '2026-11-02',
		kind: 'race',
		target_distance_m: 10_000,
		race_priority: 'C',
	});
	const move = { op: 'move_workout', workoutId: 'c-easy', date: '2026-10-30' } as const;
	const scale = { op: 'scale_week', weekIndex: 2, factor: 1.1 } as const;
	for (const ops of [[move, scale], [scale, move]]) {
		const r = applyPlanEditOps(base, [...ops], TODAY);
		const easy = r.after.workouts.find((w) => w.id === 'c-easy')!;
		assert.equal(easy.scheduled_date, '2026-10-30');
		assert.equal(easy.target_distance_m, 10_000);
		assert.equal(r.after.workouts.find((w) => w.id === 'c-tempo')!.target_distance_m, 11_000);
	}
});

test('a race already run keeps its recovery window protected from a scale-up', () => {
	// A B half marathon yesterday (10-14): seven days of recovery, 10-15 to
	// 10-21, cover every open session of week 1.
	const base = fixture();
	base.workouts.push({
		id: 'a-brace',
		week_id: 'wk0',
		scheduled_date: '2026-10-14',
		kind: 'race',
		target_distance_m: 21_097,
		race_priority: 'B',
	});
	const r = applyPlanEditOps(base, [{ op: 'scale_week', weekIndex: 0, factor: 1.1 }], TODAY);
	assert.deepEqual(r.workouts, []);
});

test('a race in a neighbouring block holds the workouts its window reaches', () => {
	const base = fixture();
	const nearby = [
		{ date: '2026-10-21', name: null, priority: 'C' as const, distanceM: 10_000, goalTimeSec: null, workoutId: 'elsewhere' },
	];
	// A C race on Wednesday 10-21 in another block: Thursday's easy run (10-22)
	// is in its two-day recovery, Saturday's (10-24) is not.
	const r = applyPlanEditOps(base, [{ op: 'scale_week', weekIndex: 1, factor: 1.1 }], TODAY, nearby);
	const after = (id: string) => r.after.workouts.find((w) => w.id === id)!.target_distance_m;
	assert.equal(after('b-easy'), 8_000);
	assert.equal(after('b-easy2'), 6_600);
});

test('an end-date B race with no distance takes the plan goal distance for its windows', () => {
	// planRaces gives the race the 50 km goal, so it tapers from 8 days out
	// (10-31), not 6: the peak week's Sunday long run (11-01, 7 days before) is
	// inside it and is not scaled up. The plan page reads the race the same way.
	const run = (goalM: number) => {
		const base = fixture();
		base.plan.goal_distance_m = goalM;
		const race = base.workouts.find((w) => w.id === 'd-race')!;
		race.target_distance_m = null;
		race.race_priority = 'B';
		const r = applyPlanEditOps(base, [{ op: 'scale_week', weekIndex: 2, factor: 1.1 }], TODAY);
		return r.after.workouts.find((w) => w.id === 'c-long')!.target_distance_m;
	};
	assert.equal(run(50_000), 24_000);
	// A road goal keeps the 6-day taper, which the long run sits outside.
	assert.equal(run(21_097), 26_400);
});
