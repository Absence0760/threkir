import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildReplanWeeks,
	DISMISSED_NUDGES_CAP,
	overrunDigits,
	parseDismissedNudges,
	planNudge,
	planNudgeKey,
	withDismissedNudge,
	workoutOverrunMetres,
	type NudgeInputRun,
	type NudgeInputWeek,
	type NudgeInputWorkout,
} from './plan_nudges';

function wo(
	id: string,
	scheduledDate: string,
	kind: string,
	targetDistanceM: number | null,
	{ completed = false, skipped = false, answered = false } = {},
): NudgeInputWorkout {
	return { id, scheduledDate, kind, targetDistanceM, completed, skipped, answered };
}

/// Plan starting Monday 2026-06-01: weeks 0-2 complete on 2026-06-24, week 3
/// current (06-22..06-28), week 4 ahead with a long run.
const START = '2026-06-01';
const TODAY = '2026-06-24';

function plan(volumes: [number, number, number], extra: Partial<NudgeInputWeek>[] = []): NudgeInputWeek[] {
	const weeks: NudgeInputWeek[] = [
		{
			weekIndex: 0,
			phase: 'build',
			targetVolumeM: volumes[0],
			workouts: [wo('l0', '2026-06-07', 'long', 26_000), wo('e0', '2026-06-02', 'easy', 8_000)],
		},
		{
			weekIndex: 1,
			phase: 'build',
			targetVolumeM: volumes[1],
			workouts: [wo('l1', '2026-06-14', 'long', 20_000, { completed: true }), wo('e1', '2026-06-09', 'easy', 8_000)],
		},
		{
			weekIndex: 2,
			phase: 'build',
			targetVolumeM: volumes[2],
			workouts: [wo('l2', '2026-06-21', 'long', 20_000, { completed: true }), wo('e2', '2026-06-16', 'easy', 8_000)],
		},
		{
			weekIndex: 3,
			phase: 'build',
			targetVolumeM: 40_000,
			workouts: [wo('e3', '2026-06-25', 'easy', 8_000), wo('l3', '2026-06-28', 'long', 22_000)],
		},
		{
			weekIndex: 4,
			phase: 'build',
			targetVolumeM: 40_000,
			workouts: [wo('e4', '2026-06-30', 'easy', 10_000), wo('l4', '2026-07-05', 'long', 22_000)],
		},
	];
	extra.forEach((e, i) => Object.assign(weeks[i], e));
	return weeks;
}

function nudge(weeks: NudgeInputWeek[], runs: NudgeInputRun[], over: Partial<Parameters<typeof planNudge>[0]> = {}) {
	const today = over.today ?? TODAY;
	return planNudge({
		planId: 'p',
		status: 'active',
		isTemplate: false,
		startDate: START,
		endDate: '2026-08-30',
		today,
		weeks: buildReplanWeeks({ startDate: START, today, weeks, runs }),
		runDates: runs.map((r) => r.date),
		dismissed: [],
		...over,
	});
}

test('workoutOverrunMetres: 3 km over a 10 km target is reported', () => {
	assert.equal(workoutOverrunMetres(10_000, 13_000), 3_000);
});

test('workoutOverrunMetres: less than 1 km over is noise', () => {
	assert.equal(workoutOverrunMetres(5_000, 5_900), null);
});

test('workoutOverrunMetres: less than 10% over a long target is noise', () => {
	assert.equal(workoutOverrunMetres(30_000, 32_500), null);
	assert.equal(workoutOverrunMetres(30_000, 33_000), 3_000);
});

test('workoutOverrunMetres: a short run, or no target, is never an over-run', () => {
	assert.equal(workoutOverrunMetres(10_000, 8_000), null);
	assert.equal(workoutOverrunMetres(null, 8_000), null);
	assert.equal(workoutOverrunMetres(0, 8_000), null);
	assert.equal(workoutOverrunMetres(10_000, null), null);
});

test('workoutOverrunMetres: a walk-run session never over-runs its estimate', () => {
	assert.equal(workoutOverrunMetres(2_050, 6_000, 'walk_run'), null);
	assert.equal(workoutOverrunMetres(5_857, 9_000, 'walk_run'), null);
	assert.equal(workoutOverrunMetres(10_000, 13_000, 'easy'), 3_000);
});

test('overrunDigits: whole units at ten or more, or when a decimal would read .0', () => {
	assert.equal(overrunDigits(3), 0);
	assert.equal(overrunDigits(2.98), 0);
	assert.equal(overrunDigits(1.9), 1);
	assert.equal(overrunDigits(12.4), 0);
});

test('parseDismissedNudges: keeps strings, reads anything else as nothing dismissed', () => {
	assert.deepEqual(parseDismissedNudges(['a', 3, 'b']), ['a', 'b']);
	assert.deepEqual(parseDismissedNudges('a'), []);
	assert.deepEqual(parseDismissedNudges(null), []);
});

test('withDismissedNudge: appends once and keeps only the newest entries', () => {
	assert.deepEqual(withDismissedNudge(['a', 'b'], 'a'), ['b', 'a']);
	const full = Array.from({ length: DISMISSED_NUDGES_CAP }, (_, i) => `k${i}`);
	const next = withDismissedNudge(full, 'new');
	assert.equal(next.length, DISMISSED_NUDGES_CAP);
	assert.equal(next[0], 'k1');
	assert.equal(next.at(-1), 'new');
});

test('buildReplanWeeks: falls back to the non-rest distances, sums runs by local day, closes weeks at their end', () => {
	const weeks = buildReplanWeeks({
		startDate: START,
		today: '2026-06-08',
		weeks: [
			{ weekIndex: 0, phase: 'build', targetVolumeM: null, workouts: [wo('a', '2026-06-02', 'easy', 8_000), wo('r', '2026-06-03', 'rest', 5_000)] },
			{ weekIndex: 1, phase: 'build', targetVolumeM: 30_000, workouts: [wo('b', '2026-06-09', 'easy', 8_000)] },
		],
		runs: [
			{ date: '2026-06-01', distanceM: 5_000 },
			{ date: '2026-06-07', distanceM: 4_000 },
			{ date: '2026-06-08', distanceM: 6_000 },
		],
	});
	assert.equal(weeks[0].plannedMetres, 8_000);
	assert.equal(weeks[0].actualMetres, 9_000);
	assert.equal(weeks[0].isComplete, true);
	assert.equal(weeks[0].workouts[0].isPast, true);
	assert.equal(weeks[1].actualMetres, 6_000);
	assert.equal(weeks[1].isComplete, false);
	assert.equal(weeks[1].workouts[0].isPast, false);
});

test('buildReplanWeeks: a walk-run week plans no distance, so it never reads as over or under', () => {
	const weeks = buildReplanWeeks({
		startDate: START,
		today: '2026-06-15',
		weeks: [
			{ weekIndex: 0, phase: 'build', targetVolumeM: 6_150, workouts: [wo('a', '2026-06-01', 'walk_run', 2_050), wo('b', '2026-06-03', 'walk_run', 2_050)] },
			{ weekIndex: 1, phase: 'build', targetVolumeM: null, workouts: [wo('c', '2026-06-08', 'walk_run', 2_050)] },
		],
		runs: [{ date: '2026-06-01', distanceM: 5_000 }, { date: '2026-06-08', distanceM: 5_000 }],
	});
	assert.equal(weeks[0].plannedMetres, 0);
	assert.equal(weeks[0].actualMetres, 5_000);
	assert.equal(weeks[1].plannedMetres, 0);
	const n = planNudge({
		planId: 'p',
		status: 'active',
		isTemplate: false,
		startDate: START,
		endDate: '2026-08-30',
		today: '2026-06-15',
		weeks,
		runDates: [],
		dismissed: [],
	});
	assert.equal(n, null);
});

test('planNudge: under plan in 2 of the last 3 weeks with a missed long run proposes the adaptive review', () => {
	const runs = [
		{ date: '2026-06-02', distanceM: 8_000 },
		{ date: '2026-06-14', distanceM: 20_000 },
		{ date: '2026-06-09', distanceM: 8_000 },
		{ date: '2026-06-21', distanceM: 20_000 },
		{ date: '2026-06-16', distanceM: 8_000 },
	];
	const n = nudge(plan([40_000, 40_000, 28_000]), runs);
	assert.deepEqual(n, {
		kind: 'adaptive_under',
		weekIndex: 2,
		key: 'p:adaptive_under:2',
		weeks: 2,
		ofWeeks: 3,
	});
});

test('planNudge: a missed long run the runner already answered is not made up again', () => {
	const runs = [
		{ date: '2026-06-02', distanceM: 8_000 },
		{ date: '2026-06-14', distanceM: 20_000 },
		{ date: '2026-06-09', distanceM: 8_000 },
		{ date: '2026-06-21', distanceM: 20_000 },
		{ date: '2026-06-16', distanceM: 8_000 },
	];
	const weeks = plan([40_000, 40_000, 28_000], [
		{ workouts: [wo('l0', '2026-06-07', 'long', 26_000, { answered: true }), wo('e0', '2026-06-02', 'easy', 8_000)] },
	]);
	const built = buildReplanWeeks({ startDate: START, today: TODAY, weeks, runs });
	assert.equal(built[0].workouts[0].skipped, true);
	assert.equal(nudge(weeks, runs), null);
});

test('planNudge: an under-run trend with nothing safe to change says nothing', () => {
	const weeks = plan([40_000, 40_000, 28_000], [{ workouts: [wo('e0', '2026-06-02', 'easy', 8_000)] }]);
	const runs = [
		{ date: '2026-06-14', distanceM: 20_000 },
		{ date: '2026-06-21', distanceM: 28_000 },
	];
	assert.equal(nudge(weeks, runs), null);
});

test('planNudge: a week well under plan anchors the weeks ahead, and outranks the trend card', () => {
	const runs = [
		{ date: '2026-06-02', distanceM: 8_000 },
		{ date: '2026-06-14', distanceM: 20_000 },
		{ date: '2026-06-21', distanceM: 12_000 },
	];
	const weeks = plan([40_000, 40_000, 40_000]);
	assert.deepEqual(nudge(weeks, runs, { anchorVolume: true }), {
		kind: 'anchor_under',
		weekIndex: 2,
		key: 'p:anchor_under:2',
		weeks: 1,
		ofWeeks: 1,
	});
	// The trend card would open the same anchored proposal, so it is not
	// offered in its place once this one is dismissed.
	assert.equal(nudge(weeks, runs, { anchorVolume: true, dismissed: ['p:anchor_under:2'] }), null);
});

test('planNudge: with the gate off no week is anchored, and the trend card is offered as before', () => {
	const runs = [
		{ date: '2026-06-02', distanceM: 8_000 },
		{ date: '2026-06-14', distanceM: 20_000 },
		{ date: '2026-06-21', distanceM: 12_000 },
	];
	const weeks = plan([40_000, 40_000, 40_000]);
	assert.equal(nudge(weeks, runs)?.kind, 'adaptive_under');
	assert.equal(nudge(weeks, runs, { anchorVolume: false })?.kind, 'adaptive_under');
	assert.equal(nudge(weeks, runs, { dismissed: ['p:adaptive_under:2'] }), null);
});

test('planNudge: weeks away from a resumed plan re-anchor it, whatever the last week ran', () => {
	const runs = [
		{ date: '2026-06-02', distanceM: 8_000 },
		{ date: '2026-06-07', distanceM: 26_000 },
		{ date: '2026-06-09', distanceM: 8_000 },
		{ date: '2026-06-14', distanceM: 20_000 },
		{ date: '2026-06-16', distanceM: 8_000 },
		{ date: '2026-06-21', distanceM: 20_000 },
	];
	// A resume pushed weeks 3 and 4 back four weeks, to indices 7 and 8.
	const weeks = plan([34_000, 28_000, 28_000], [
		{},
		{},
		{},
		{ weekIndex: 7, workouts: [wo('e7', '2026-07-21', 'easy', 8_000), wo('l7', '2026-07-26', 'long', 22_000)] },
		{ weekIndex: 8, workouts: [wo('e8', '2026-07-28', 'easy', 10_000), wo('l8', '2026-08-02', 'long', 22_000)] },
	]);
	assert.equal(nudge(weeks, runs, { today: '2026-07-15' }), null);
	assert.deepEqual(nudge(weeks, runs, { today: '2026-07-15', anchorVolume: true }), {
		kind: 'anchor_return',
		weekIndex: 2,
		key: 'p:anchor_return:2',
		weeks: 4,
		ofWeeks: 4,
	});
});

test('planNudge: one week more than 20% over plan proposes the ease-off', () => {
	const runs = [
		{ date: '2026-06-07', distanceM: 28_000 },
		{ date: '2026-06-14', distanceM: 28_000 },
		{ date: '2026-06-21', distanceM: 36_000 },
	];
	const n = nudge(plan([28_000, 28_000, 28_000]), runs);
	assert.equal(n?.kind, 'ease_over');
	assert.equal(n?.key, planNudgeKey('p', 'ease_over', 2));
	assert.equal(n?.weeks, 1);
	assert.equal(n?.ofWeeks, 1);
});

test('planNudge: runs on rest days in 2 of the last 3 weeks get the rest-day note', () => {
	const runs = [
		{ date: '2026-06-07', distanceM: 20_000 },
		{ date: '2026-06-02', distanceM: 8_000 },
		{ date: '2026-06-03', distanceM: 4_000 },
		{ date: '2026-06-14', distanceM: 20_000 },
		{ date: '2026-06-09', distanceM: 4_000 },
		{ date: '2026-06-20', distanceM: 4_000 },
		{ date: '2026-06-21', distanceM: 20_000 },
		{ date: '2026-06-16', distanceM: 12_000 },
	];
	const n = nudge(plan([36_000, 32_000, 32_000]), runs);
	assert.equal(n?.kind, 'rest_day_runs');
	assert.equal(n?.weeks, 2);
	assert.equal(n?.ofWeeks, 3);
});

test('planNudge: a rest-day run in only one week is not a habit', () => {
	const runs = [
		{ date: '2026-06-07', distanceM: 20_000 },
		{ date: '2026-06-02', distanceM: 8_000 },
		{ date: '2026-06-03', distanceM: 4_000 },
		{ date: '2026-06-14', distanceM: 20_000 },
		{ date: '2026-06-09', distanceM: 8_000 },
		{ date: '2026-06-21', distanceM: 20_000 },
		{ date: '2026-06-16', distanceM: 8_000 },
	];
	assert.equal(nudge(plan([32_000, 28_000, 28_000]), runs), null);
});

test('planNudge: a dismissed occurrence gives way to the next one, and a new week brings it back', () => {
	const runs = [
		{ date: '2026-06-07', distanceM: 28_000 },
		{ date: '2026-06-14', distanceM: 28_000 },
		{ date: '2026-06-20', distanceM: 8_000 },
		{ date: '2026-06-21', distanceM: 28_000 },
		{ date: '2026-06-13', distanceM: 8_000 },
	];
	const weeks = plan([28_000, 28_000, 28_000]);
	assert.equal(nudge(weeks, runs)?.kind, 'ease_over');
	assert.equal(nudge(weeks, runs, { dismissed: ['p:ease_over:2'] })?.kind, 'rest_day_runs');
	assert.equal(nudge(weeks, runs, { dismissed: ['p:ease_over:2', 'p:rest_day_runs:2'] }), null);
	assert.equal(nudge(weeks, runs, { dismissed: ['p:ease_over:1'] })?.kind, 'ease_over');
});

test('planNudge: nothing for a paused, finished, template or not-yet-started plan', () => {
	const runs = [
		{ date: '2026-06-07', distanceM: 28_000 },
		{ date: '2026-06-14', distanceM: 28_000 },
		{ date: '2026-06-21', distanceM: 36_000 },
	];
	const weeks = plan([28_000, 28_000, 28_000]);
	assert.equal(nudge(weeks, runs, { status: 'paused' }), null);
	assert.equal(nudge(weeks, runs, { status: 'completed' }), null);
	assert.equal(nudge(weeks, runs, { isTemplate: true }), null);
	assert.equal(nudge(weeks, runs, { endDate: '2026-06-23' }), null);
	assert.equal(nudge(weeks, runs, { startDate: '2026-06-25' }), null);
});

test('planNudge: nothing before the first week has ended', () => {
	const runs = [{ date: '2026-06-02', distanceM: 30_000 }];
	assert.equal(nudge(plan([28_000, 28_000, 28_000]), runs, { today: '2026-06-05' }), null);
});

test('planNudge: a judged week that overlaps a break says nothing, and a later one is judged again', () => {
	const runs = [
		{ date: '2026-06-07', distanceM: 28_000 },
		{ date: '2026-06-14', distanceM: 28_000 },
		{ date: '2026-06-21', distanceM: 36_000 },
	];
	const weeks = plan([28_000, 28_000, 28_000]);
	assert.equal(nudge(weeks, runs, { breakFromIso: '2026-06-21', breakUntilIso: '2026-06-24' }), null);
	assert.equal(nudge(weeks, runs, { breakFromIso: '2026-06-01', breakUntilIso: '2026-06-14' })?.kind, 'ease_over');
	assert.equal(nudge(weeks, runs, { breakFromIso: '2026-06-22', breakUntilIso: '2026-06-24' })?.kind, 'ease_over');
});
