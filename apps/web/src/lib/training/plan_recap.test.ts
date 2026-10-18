import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	assemblePlanRecap,
	fiveKSecondsAtVdot,
	recapGoalRace,
	recapRaceRun,
	recapRaceVdot,
	type RecapPlan,
	type PlanRecapRun,
	type RecapWorkout
} from './plan_recap.ts';
import type { PlanRace } from './plan_races.ts';
import { vdotFromRace } from './training.ts';

// Mirror: apps/mobile_android/test/plan_recap_test.dart.

const plan: RecapPlan = {
	start_date: '2026-03-01',
	end_date: '2026-04-26',
	goal_distance_m: 21097.5,
	goal_time_seconds: 5700,
	trimmed_at: null
};

function wo(id: string, date: string, kind: string, extra: Partial<RecapWorkout> = {}): RecapWorkout {
	return {
		id,
		scheduled_date: date,
		kind,
		target_distance_m: kind === 'rest' ? null : 10_000,
		target_duration_seconds: null,
		...extra
	};
}

function run(id: string, date: string, distanceM: number, durationS: number, extra: Partial<PlanRecapRun> = {}): PlanRecapRun {
	return { id, date, distanceM, durationS, activityType: 'run', isDnf: false, ...extra };
}

function race(date: string, priority: 'A' | 'B' | 'C', workoutId: string | null, distanceM = 21097.5): PlanRace {
	return { date, name: null, priority, distanceM, goalTimeSec: null, workoutId };
}

test('recapGoalRace: the end-date race, else the last A race, else the last race', () => {
	assert.equal(recapGoalRace([race('2026-04-05', 'B', 'b'), race('2026-04-26', 'A', 'a')], '2026-04-26')?.workoutId, 'a');
	assert.equal(
		recapGoalRace([race('2026-03-20', 'A', 'a1'), race('2026-04-05', 'A', 'a2'), race('2026-04-12', 'C', 'c')], '2026-04-26')
			?.workoutId,
		'a2'
	);
	assert.equal(recapGoalRace([race('2026-04-05', 'B', 'b'), race('2026-04-12', 'C', 'c')], '2026-04-26')?.workoutId, 'c');
	assert.equal(recapGoalRace([], '2026-04-26'), null);
});

test('sessions: the ring counts, plus the skipped sessions it leaves out', () => {
	const recap = assemblePlanRecap({
		plan,
		workouts: [
			wo('w1', '2026-03-01', 'long', { manually_completed: true }),
			wo('w2', '2026-03-02', 'rest', { manually_completed: true }),
			wo('w3', '2026-03-03', 'easy', { skipped_at: '2026-03-03T08:00:00Z' }),
			wo('w4', '2026-03-04', 'tempo'),
			wo('w5', '2026-04-26', 'race', { completed_run_id: 'r-race' })
		],
		runs: [run('r-race', '2026-04-26', 21_200, 5400)],
		records: [],
		todayIso: '2026-04-27'
	});
	assert.deepEqual(recap.sessions, { completed: 2, total: 3, pct: 67, skipped: 1 });
});

test('distance: a linked run counts its real distance, a ticked workout its target', () => {
	const recap = assemblePlanRecap({
		plan,
		workouts: [
			wo('w1', '2026-03-01', 'long', { completed_run_id: 'r1', target_distance_m: 16_000 }),
			wo('w2', '2026-03-03', 'easy', { manually_completed: true, target_distance_m: 8000 }),
			wo('w3', '2026-03-05', 'easy', { target_distance_m: 6000 }),
			wo('w4', '2026-03-07', 'easy', { skipped_at: '2026-03-07T08:00:00Z', target_distance_m: 5000 })
		],
		runs: [run('r1', '2026-03-01', 17_500, 6000)],
		records: [],
		todayIso: '2026-04-27'
	});
	assert.deepEqual(recap.volume, { basis: 'distance', done: 25_500, planned: 30_000 });
});

test('a walk-run plan reports time, not distance', () => {
	const timed = (id: string, date: string, extra: Partial<RecapWorkout> = {}) =>
		wo(id, date, 'walk_run', { target_distance_m: 3000, target_duration_seconds: 1800, ...extra });
	const recap = assemblePlanRecap({
		plan,
		workouts: [
			timed('w1', '2026-03-01', { completed_run_id: 'r1' }),
			timed('w2', '2026-03-03', { manually_completed: true }),
			timed('w3', '2026-03-05'),
			wo('w4', '2026-03-06', 'rest')
		],
		runs: [run('r1', '2026-03-01', 3100, 2000)],
		records: [],
		todayIso: '2026-04-27'
	});
	assert.deepEqual(recap.volume, { basis: 'time', done: 3800, planned: 5400 });
});

test('records: only those set inside the plan window, by date then distance', () => {
	const recap = assemblePlanRecap({
		plan,
		workouts: [],
		runs: [],
		records: [
			{ distance: '5k', timeS: 1190, date: '2026-02-28', runId: 'a' },
			{ distance: '10k', timeS: 2500, date: '2026-04-26', runId: 'b' },
			{ distance: '5k', timeS: 1180, date: '2026-04-26', runId: 'b' },
			{ distance: '1_mile', timeS: 360, date: '2026-03-01', runId: 'c' },
			{ distance: 'marathon', timeS: 12_600, date: '2026-04-27', runId: 'd' }
		],
		todayIso: '2026-04-27'
	});
	assert.deepEqual(
		recap.records.map((r) => `${r.date} ${r.distance}`),
		['2026-03-01 1_mile', '2026-04-26 10k', '2026-04-26 5k']
	);
});

test('the race workout linked to a run gives the race run and its VDOT', () => {
	const recap = assemblePlanRecap({
		plan,
		workouts: [wo('w-race', '2026-04-26', 'race', { completed_run_id: 'r-race', race_name: 'Spring Half', target_distance_m: null })],
		runs: [run('r-race', '2026-04-26', 21_097.5, 5400)],
		records: [],
		todayIso: '2026-04-27'
	});
	assert.equal(recap.race?.name, 'Spring Half');
	assert.equal(recap.race?.distanceM, 21097.5);
	assert.deepEqual(recap.race?.run, { id: 'r-race', distanceM: 21_097.5, durationS: 5400, isDnf: false });
	assert.equal(recap.race?.raced, true);
	assert.equal(recap.race?.vdot, 51);
});

test('an unlinked race workout has no run; a ticked one was still raced', () => {
	const sameDay = [run('r-other', '2026-04-26', 21_000, 5600)];
	const unlinked = assemblePlanRecap({
		plan,
		workouts: [wo('w-race', '2026-04-26', 'race')],
		runs: sameDay,
		records: [],
		todayIso: '2026-04-27'
	});
	assert.equal(unlinked.race?.run, null);
	assert.equal(unlinked.race?.raced, false);
	assert.equal(unlinked.next.recovery, null);
	const ticked = assemblePlanRecap({
		plan,
		workouts: [wo('w-race', '2026-04-26', 'race', { manually_completed: true })],
		runs: sameDay,
		records: [],
		todayIso: '2026-04-27'
	});
	assert.equal(ticked.race?.run, null);
	assert.equal(ticked.race?.raced, true);
	assert.equal(ticked.race?.vdot, null);
});

test('a race with no workout row takes the longest run-family run that day covering 75% of it', () => {
	const goal = race('2026-04-26', 'A', null, 10_000);
	const runs = [
		run('jog', '2026-04-26', 3000, 1100),
		run('ride', '2026-04-26', 40_000, 4000, { activityType: 'cycle' }),
		run('race', '2026-04-26', 10_050, 2500),
		run('eve', '2026-04-25', 12_000, 3600)
	];
	assert.equal(recapRaceRun(goal, [], runs)?.id, 'race');
	assert.equal(recapRaceRun(goal, [], [run('jog', '2026-04-26', 7000, 2400)]), null);
	assert.equal(recapRaceRun(goal, [], [run('ok', '2026-04-26', 7500, 2400)])?.id, 'ok');
});

test('recapRaceVdot: null for a DNF, a walk, an ultra, or no time', () => {
	const r = { id: 'r', distanceM: 21_097.5, durationS: 5400, isDnf: false };
	assert.equal(recapRaceVdot(r, null), 51);
	assert.equal(recapRaceVdot({ ...r, isDnf: true }, 'run'), null);
	assert.equal(recapRaceVdot(r, 'walk'), null);
	assert.equal(recapRaceVdot({ ...r, distanceM: 50_000, durationS: 18_000 }, 'run'), null);
	assert.equal(recapRaceVdot({ ...r, durationS: 0 }, 'run'), null);
	assert.equal(recapRaceVdot(null, 'run'), null);
});

test('fiveKSecondsAtVdot inverts vdotFromRace at 5 km', () => {
	assert.equal(fiveKSecondsAtVdot(vdotFromRace(5000, 1200)), 1200);
	assert.equal(fiveKSecondsAtVdot(51), 1176);
	assert.equal(fiveKSecondsAtVdot(0), null);
	assert.equal(fiveKSecondsAtVdot(Number.NaN), null);
});

test('next: recovery after a marathon pushes the next plan past the wizard default', () => {
	const marathon: RecapPlan = { ...plan, goal_distance_m: 42_195, goal_time_seconds: null };
	const recap = assemblePlanRecap({
		plan: marathon,
		workouts: [wo('w-race', '2026-04-26', 'race', { completed_run_id: 'r', target_distance_m: 42_195 })],
		runs: [run('r', '2026-04-26', 42_195, 12_600)],
		records: [],
		todayIso: '2026-04-27'
	});
	assert.equal(recap.race?.vdot, 44.6);
	assert.deepEqual(recap.next.recovery, { days: 14, untilIso: '2026-05-10' });
	assert.equal(recap.next.startIso, '2026-05-17');
	assert.equal(recap.next.seed5kSec, fiveKSecondsAtVdot(44.6));
});

test('next: a recovery already over and a race past the recent window seed nothing', () => {
	const recap = assemblePlanRecap({
		plan,
		workouts: [wo('w-race', '2026-04-26', 'race', { completed_run_id: 'r', target_distance_m: 21_097.5 })],
		runs: [run('r', '2026-04-26', 21_097.5, 5400)],
		records: [],
		todayIso: '2026-07-01'
	});
	assert.equal(recap.next.recovery, null);
	assert.equal(recap.next.startIso, '2026-07-12');
	assert.equal(recap.next.seed5kSec, null);
	assert.equal(recap.race?.vdot, 51);
});

test('a plan ended early with no race rows has no race and starts on the default', () => {
	const recap = assemblePlanRecap({
		plan: { ...plan, trimmed_at: '2026-04-01T10:00:00Z' },
		workouts: [wo('w1', '2026-03-01', 'long', { manually_completed: true })],
		runs: [],
		records: [],
		todayIso: '2026-04-27'
	});
	assert.equal(recap.race, null);
	assert.deepEqual(recap.next, { recovery: null, startIso: '2026-05-10', seed5kSec: null });
});
