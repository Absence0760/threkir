import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	weeklyDrift,
	weeklyDriftToDate,
	missedWorkoutAdvice,
	PLAN_DRIFT_THRESHOLD,
} from './plan_adherence';

// ─────────────────────── weeklyDrift ───────────────────────

test('weeklyDrift: on-track when actual matches planned', () => {
	const d = weeklyDrift(40_000, 41_000);
	assert.equal(d.direction, 'on_track');
	assert.equal(d.flagged, false);
});

test('weeklyDrift: flags under-running past the threshold', () => {
	// 40 km planned, 28 km actual → −30% drift.
	const d = weeklyDrift(40_000, 28_000);
	assert.equal(d.direction, 'under');
	assert.equal(d.flagged, true);
	assert.ok(d.driftFraction < -PLAN_DRIFT_THRESHOLD);
});

test('weeklyDrift: flags over-running past the threshold', () => {
	// 40 km planned, 52 km actual → +30% drift (the easy-week trap).
	const d = weeklyDrift(40_000, 52_000);
	assert.equal(d.direction, 'over');
	assert.equal(d.flagged, true);
	assert.ok(d.driftFraction > PLAN_DRIFT_THRESHOLD);
});

test('weeklyDrift: just inside the threshold is not flagged', () => {
	// 40 km planned, 47 km actual → +17.5%, under the 20% bar.
	const d = weeklyDrift(40_000, 47_000);
	assert.equal(d.direction, 'on_track');
	assert.equal(d.flagged, false);
});

test('weeklyDrift: no planned volume yields a neutral, unflagged result', () => {
	const d = weeklyDrift(0, 30_000);
	assert.equal(d.direction, 'on_track');
	assert.equal(d.flagged, false);
	assert.equal(d.driftFraction, 0);
});

test('weeklyDrift: clamps negative actual to zero', () => {
	const d = weeklyDrift(40_000, -5);
	assert.equal(d.actualMetres, 0);
	assert.equal(d.direction, 'under');
});

// ─────────────────────── weeklyDriftToDate ───────────────────────
//
// A plan week running Mon 2026-03-02 → Sun 2026-03-08, 50 km over five
// running days: Mon 8, Wed 10, Thu 8, Sat 6, Sun 18.

const WEEK = [
	{ scheduledDate: '2026-03-02', kind: 'easy', targetDistanceM: 8_000 },
	{ scheduledDate: '2026-03-03', kind: 'rest', targetDistanceM: null },
	{ scheduledDate: '2026-03-04', kind: 'tempo', targetDistanceM: 10_000 },
	{ scheduledDate: '2026-03-05', kind: 'easy', targetDistanceM: 8_000 },
	{ scheduledDate: '2026-03-06', kind: 'rest', targetDistanceM: null },
	{ scheduledDate: '2026-03-07', kind: 'easy', targetDistanceM: 6_000 },
	{ scheduledDate: '2026-03-08', kind: 'long', targetDistanceM: 18_000 },
];

test('weeklyDriftToDate: mid-week and exactly on the plan so far is not flagged', () => {
	// Thursday morning, Mon + Wed run as prescribed. The whole-week
	// baseline read this as 18 of 50 km — 64% under plan — every week.
	const d = weeklyDriftToDate({
		workouts: WEEK,
		runs: [
			{ date: '2026-03-02', distanceM: 8_000 },
			{ date: '2026-03-04', distanceM: 10_000 },
		],
		today: '2026-03-05',
	});
	assert.equal(d.plannedMetres, 18_000);
	assert.equal(d.actualMetres, 18_000);
	assert.equal(d.direction, 'on_track');
	assert.equal(d.flagged, false);
});

test('weeklyDriftToDate: genuinely behind on the elapsed days still flags', () => {
	// Same Thursday, but Wednesday's tempo never happened.
	const d = weeklyDriftToDate({
		workouts: WEEK,
		runs: [{ date: '2026-03-02', distanceM: 8_000 }],
		today: '2026-03-05',
	});
	assert.equal(d.plannedMetres, 18_000);
	assert.equal(d.direction, 'under');
	assert.equal(d.flagged, true);
});

test('weeklyDriftToDate: over-running the elapsed days flags', () => {
	const d = weeklyDriftToDate({
		workouts: WEEK,
		runs: [
			{ date: '2026-03-02', distanceM: 14_000 },
			{ date: '2026-03-04', distanceM: 16_000 },
		],
		today: '2026-03-05',
	});
	assert.equal(d.direction, 'over');
	assert.ok(d.driftFraction > PLAN_DRIFT_THRESHOLD);
});

test('weeklyDriftToDate: a session due at the end of today is not yet owed', () => {
	// Wednesday, Monday's 8 km done and Wednesday's tempo still ahead of
	// the runner. Counting today's 10 km would read as 44% under plan.
	const d = weeklyDriftToDate({
		workouts: WEEK,
		runs: [{ date: '2026-03-02', distanceM: 8_000 }],
		today: '2026-03-04',
	});
	assert.equal(d.plannedMetres, 8_000);
	assert.equal(d.flagged, false);
});

test('weeklyDriftToDate: a run already done today does not read as over-running', () => {
	// Thursday, and Thursday's 8 km is already banked. It belongs to a day
	// that has not ended, so it counts on neither side.
	const d = weeklyDriftToDate({
		workouts: WEEK,
		runs: [
			{ date: '2026-03-02', distanceM: 8_000 },
			{ date: '2026-03-04', distanceM: 10_000 },
			{ date: '2026-03-05', distanceM: 8_000 },
		],
		today: '2026-03-05',
	});
	assert.equal(d.actualMetres, 18_000);
	assert.equal(d.direction, 'on_track');
});

test('weeklyDriftToDate: the first day of the week has nothing to judge', () => {
	const d = weeklyDriftToDate({ workouts: WEEK, runs: [], today: '2026-03-02' });
	assert.equal(d.plannedMetres, 0);
	assert.equal(d.direction, 'on_track');
	assert.equal(d.flagged, false);
});

test('weeklyDriftToDate: once the week has fully elapsed the baseline is the whole week', () => {
	const d = weeklyDriftToDate({
		workouts: WEEK,
		runs: [
			{ date: '2026-03-02', distanceM: 8_000 },
			{ date: '2026-03-04', distanceM: 10_000 },
			{ date: '2026-03-05', distanceM: 8_000 },
			{ date: '2026-03-08', distanceM: 9_000 },
		],
		today: '2026-03-09',
	});
	assert.equal(d.plannedMetres, 50_000);
	assert.equal(d.actualMetres, 35_000);
	assert.equal(d.direction, 'under');
});

test("weeklyDriftToDate: a declared week volume is scaled by the schedule's shape", () => {
	// The week is worth 60 km; the workouts place 18 of their 50 km before
	// Thursday, so 36% of the declared volume is owed.
	const d = weeklyDriftToDate({
		workouts: WEEK,
		runs: [{ date: '2026-03-02', distanceM: 21_600 }],
		today: '2026-03-05',
		weekTargetVolumeM: 60_000,
	});
	assert.equal(d.plannedMetres, 21_600);
	assert.equal(d.direction, 'on_track');
});

test('weeklyDriftToDate: a week volume no workout carries cannot be placed in time', () => {
	const d = weeklyDriftToDate({
		workouts: WEEK.map((w) => ({ ...w, targetDistanceM: null })),
		runs: [],
		today: '2026-03-05',
		weekTargetVolumeM: 40_000,
	});
	assert.equal(d.plannedMetres, 0);
	assert.equal(d.flagged, false);
});

test('weeklyDriftToDate: a rest day carrying a distance is excluded from the baseline', () => {
	const d = weeklyDriftToDate({
		workouts: [
			{ scheduledDate: '2026-03-02', kind: 'easy', targetDistanceM: 8_000 },
			{ scheduledDate: '2026-03-03', kind: 'rest', targetDistanceM: 5_000 },
		],
		runs: [{ date: '2026-03-02', distanceM: 8_000 }],
		today: '2026-03-04',
	});
	assert.equal(d.plannedMetres, 8_000);
	assert.equal(d.direction, 'on_track');
});

// ─────────────────────── missedWorkoutAdvice ───────────────────────

test('missedWorkoutAdvice: base/build long run is worth making up', () => {
	const a = missedWorkoutAdvice({
		kind: 'long',
		isTaper: false,
		recoveryWeekImminent: false,
	});
	assert.equal(a.recommendation, 'make_up');
	assert.equal(a.reason, 'key_session');
});

test('missedWorkoutAdvice: skip a long run missed in the taper', () => {
	const a = missedWorkoutAdvice({
		kind: 'long',
		isTaper: true,
		recoveryWeekImminent: false,
	});
	assert.equal(a.recommendation, 'skip');
	assert.equal(a.reason, 'taper');
});

test('missedWorkoutAdvice: skip when a recovery week is imminent', () => {
	const a = missedWorkoutAdvice({
		kind: 'long',
		isTaper: false,
		recoveryWeekImminent: true,
	});
	assert.equal(a.recommendation, 'skip');
	assert.equal(a.reason, 'recovery_soon');
});

test('missedWorkoutAdvice: taper takes precedence over recovery-soon', () => {
	const a = missedWorkoutAdvice({
		kind: 'long',
		isTaper: true,
		recoveryWeekImminent: true,
	});
	assert.equal(a.reason, 'taper');
});

test('missedWorkoutAdvice: a missed quality session is just skipped', () => {
	for (const kind of ['tempo', 'interval', 'easy', 'marathon_pace']) {
		const a = missedWorkoutAdvice({ kind, isTaper: false, recoveryWeekImminent: false });
		assert.equal(a.recommendation, 'skip');
		assert.equal(a.reason, 'not_long_run');
	}
});
