import { test } from 'node:test';
import assert from 'node:assert/strict';
import { anchorToActualVolume, preferVolumeAnchor } from './plan_volume_anchor';
import type { ReplanChange, ReplanWeek, ReplanWorkout } from './plan_replan';

function wo(
	id: string,
	scheduledDate: string,
	kind: string,
	targetDistanceM: number | null,
	{ completed = false, skipped = false, isPast = false } = {},
): ReplanWorkout {
	return { id, scheduledDate, kind, targetDistanceM, completed, skipped, isPast };
}

function week(
	weekIndex: number,
	plannedMetres: number,
	actualMetres: number,
	isComplete: boolean,
	workouts: ReplanWorkout[],
	phase = 'build',
): ReplanWeek {
	return { weekIndex, phase, plannedMetres, actualMetres, isComplete, workouts };
}

/// A 40 km week of four future sessions: long 16, easy 10, tempo 8, easy 6.
function fullWeek(weekIndex: number, date: string, phase = 'build'): ReplanWeek {
	return week(
		weekIndex,
		40_000,
		0,
		false,
		[
			wo(`l${weekIndex}`, date, 'long', 16_000),
			wo(`e${weekIndex}`, date, 'easy', 10_000),
			wo(`t${weekIndex}`, date, 'tempo', 8_000),
			wo(`r${weekIndex}`, date, 'easy', 6_000),
			wo(`x${weekIndex}`, date, 'rest', null),
		],
		phase,
	);
}

function byId(changes: ReplanChange[]): Map<string, number> {
	return new Map(changes.map((c) => [c.workoutId, c.toMetres]));
}

test('anchorToActualVolume: an on-track week proposes nothing', () => {
	const weeks = [week(0, 40_000, 38_000, true, []), fullWeek(1, '2026-06-08')];
	assert.equal(anchorToActualVolume({ weeks }), null);
});

test('anchorToActualVolume: a niggle week caps next week at 10% over what was run', () => {
	const weeks = [week(0, 40_000, 20_000, true, []), fullWeek(1, '2026-06-08')];
	const a = anchorToActualVolume({ weeks });
	assert.ok(a);
	assert.equal(a.anchorWeekIndex, 0);
	assert.equal(a.anchorMetres, 20_000);
	assert.equal(a.returning, false);
	// cap 22 km over 40 km: factor 0.55, each session floored to the 100 m.
	const to = byId(a.changes);
	assert.equal(to.get('l1'), 8_800);
	assert.equal(to.get('e1'), 5_500);
	assert.equal(to.get('t1'), 4_400);
	assert.equal(to.get('r1'), 3_300);
	assert.ok(a.changes.every((c) => c.reason === 'anchor_actual_volume'));
	const total = [...to.values()].reduce((s, v) => s + v, 0);
	assert.ok(total <= 22_000);
});

test('anchorToActualVolume: the climb grows 10% a week from what each week prescribes', () => {
	const weeks = [
		week(0, 40_000, 20_000, true, []),
		fullWeek(1, '2026-06-08'),
		fullWeek(2, '2026-06-15'),
	];
	const a = anchorToActualVolume({ weeks });
	assert.ok(a);
	const to = byId(a.changes);
	const week1 = ['l1', 'e1', 't1', 'r1'].reduce((s, id) => s + (to.get(id) ?? 0), 0);
	const week2 = ['l2', 'e2', 't2', 'r2'].reduce((s, id) => s + (to.get(id) ?? 0), 0);
	assert.equal(week1, 22_000);
	assert.ok(week2 <= week1 * 1.1);
	assert.ok(week2 > week1);
});

test('anchorToActualVolume: the climb ends once the plan fits, and later weeks are untouched', () => {
	const weeks = [
		week(0, 40_000, 30_000, true, []),
		fullWeek(1, '2026-06-08'),
		fullWeek(2, '2026-06-15'),
		fullWeek(3, '2026-06-22'),
	];
	const a = anchorToActualVolume({ weeks });
	assert.ok(a);
	// 33 km, then 36.3 km, then 39.9 km caps: all three still cap; a 40 km
	// week never moves in a fourth. Every change is in weeks 1..3.
	assert.ok(a.changes.every((c) => /[1-3]$/.test(c.workoutId)));
	const weeks2 = [week(0, 40_000, 30_000, true, []), fullWeek(1, '2026-06-08'), week(2, 20_000, 0, false, [wo('s', '2026-06-15', 'easy', 20_000)])];
	const b = anchorToActualVolume({ weeks: weeks2 });
	assert.ok(b);
	assert.ok(!b.changes.some((c) => c.workoutId === 's'));
});

test('anchorToActualVolume: taper and race weeks are never touched, and the climb stops there', () => {
	const weeks = [
		week(0, 40_000, 10_000, true, []),
		fullWeek(1, '2026-06-08', 'taper'),
		fullWeek(2, '2026-06-15', 'build'),
	];
	assert.equal(anchorToActualVolume({ weeks }), null);
});

test('anchorToActualVolume: no session goes under the 3 km floor, and one already under it stays', () => {
	const weeks = [
		week(0, 30_000, 2_000, true, []),
		week(1, 30_000, 0, false, [
			wo('a', '2026-06-08', 'long', 20_000),
			wo('b', '2026-06-09', 'recovery', 2_500),
			wo('c', '2026-06-10', 'easy', 7_500),
		]),
	];
	const a = anchorToActualVolume({ weeks });
	assert.ok(a);
	const to = byId(a.changes);
	assert.equal(to.get('a'), 3_000);
	assert.equal(to.get('c'), 3_000);
	assert.equal(to.has('b'), false);
});

test('anchorToActualVolume: done sessions count as prescribed, missed ones count nothing, past ones never change', () => {
	const weeks = [
		week(0, 40_000, 20_000, true, []),
		week(1, 40_000, 0, false, [
			wo('done', '2026-06-08', 'long', 12_000, { completed: true, isPast: true }),
			wo('missed', '2026-06-09', 'easy', 10_000, { isPast: true }),
			wo('ahead', '2026-06-12', 'easy', 18_000),
		]),
	];
	const a = anchorToActualVolume({ weeks });
	assert.ok(a);
	// 22 km cap less the 12 km done leaves 10 km for the one session ahead.
	assert.deepEqual(
		a.changes.map((c) => [c.workoutId, c.toMetres]),
		[['ahead', 10_000]],
	);
});

test('anchorToActualVolume: rest, race and skipped sessions are neither counted nor changed', () => {
	const weeks = [
		week(0, 40_000, 20_000, true, []),
		week(1, 40_000, 0, false, [
			wo('race', '2026-06-08', 'race', 10_000),
			wo('skip', '2026-06-09', 'easy', 10_000, { skipped: true }),
			wo('a', '2026-06-10', 'easy', 30_000),
		]),
	];
	const a = anchorToActualVolume({ weeks });
	assert.ok(a);
	assert.deepEqual(
		a.changes.map((c) => [c.workoutId, c.toMetres]),
		[['a', 22_000]],
	);
});

test('anchorToActualVolume: a resumed walk-run plan keeps its sessions in minutes', () => {
	const weeks = [
		week(0, 10_000, 8_000, true, []),
		week(5, 12_000, 0, false, [
			wo('w1', '2026-07-06', 'walk_run', 4_000),
			wo('w2', '2026-07-08', 'walk_run', 4_000),
			wo('w3', '2026-07-10', 'walk_run', 4_000),
		]),
	];
	assert.equal(anchorToActualVolume({ weeks }), null);
});

test('anchorToActualVolume: a week with no running is a break, and the anchor is the last week that had some', () => {
	const weeks = [
		week(0, 40_000, 30_000, true, []),
		week(1, 40_000, 0, true, []),
		fullWeek(2, '2026-06-15'),
	];
	const a = anchorToActualVolume({ weeks });
	assert.ok(a);
	assert.equal(a.anchorWeekIndex, 0);
	assert.equal(a.idleWeeks, 1);
	assert.equal(a.returning, false);
	const total = a.changes.reduce((s, c) => s + c.toMetres, 0);
	assert.ok(total <= 33_000);
});

test('anchorToActualVolume: four weeks away restarts at half of what was last run', () => {
	// A resume pushed the plan back four weeks: indices 1..4 have no rows.
	const weeks = [week(0, 40_000, 36_000, true, []), fullWeek(5, '2026-07-06')];
	const a = anchorToActualVolume({ weeks });
	assert.ok(a);
	assert.equal(a.idleWeeks, 4);
	assert.equal(a.returning, true);
	// An 18 km cap: 7.2 + 4.5 + 3.6 km, and the 6 km run held at the 3 km
	// floor rather than scaled to 2.7 km, so the floor is what overshoots.
	const to = byId(a.changes);
	assert.deepEqual(
		['l5', 'e5', 't5', 'r5'].map((id) => to.get(id)),
		[7_200, 4_500, 3_600, 3_000],
	);
});

test('anchorToActualVolume: no completed week with running, or nothing ahead, proposes nothing', () => {
	assert.equal(
		anchorToActualVolume({ weeks: [week(0, 40_000, 0, true, []), fullWeek(1, '2026-06-08')] }),
		null,
	);
	assert.equal(anchorToActualVolume({ weeks: [week(0, 40_000, 10_000, true, [])] }), null);
	assert.equal(anchorToActualVolume({ weeks: [fullWeek(0, '2026-06-01')] }), null);
});

test('anchorToActualVolume: a week already anchored proposes nothing more', () => {
	const ahead = fullWeek(1, '2026-06-08');
	const weeks = [week(0, 40_000, 20_000, true, []), ahead];
	const a = anchorToActualVolume({ weeks });
	assert.ok(a);
	const to = byId(a.changes);
	const applied = {
		...ahead,
		workouts: ahead.workouts.map((x) => ({ ...x, targetDistanceM: to.get(x.id) ?? x.targetDistanceM })),
	};
	assert.equal(anchorToActualVolume({ weeks: [weeks[0], applied] }), null);
});

test('anchorToActualVolume: a week run as its anchored sessions prescribed is not short', () => {
	// The week's target stays 40 km after an anchor; its sessions ask for 22.
	const anchored = week(0, 40_000, 21_000, true, [
		wo('l0', '2026-06-07', 'long', 12_000, { completed: true, isPast: true }),
		wo('e0', '2026-06-03', 'easy', 10_000, { completed: true, isPast: true }),
		wo('x0', '2026-06-02', 'rest', null, { isPast: true }),
	]);
	assert.equal(anchorToActualVolume({ weeks: [anchored, fullWeek(1, '2026-06-08')] }), null);
	const short = { ...anchored, actualMetres: 15_000 };
	const a = anchorToActualVolume({ weeks: [short, fullWeek(1, '2026-06-08')] });
	assert.ok(a);
	assert.equal(a.anchorMetres, 15_000);
});

test('preferVolumeAnchor: the anchor replaces every other proposal, and nothing changes without one', () => {
	const other: ReplanChange[] = [
		{
			workoutId: 'l1',
			scheduledDate: '2026-06-08',
			reason: 'make_up_long',
			field: 'target_distance_m',
			fromMetres: 16_000,
			toMetres: 18_400,
		},
	];
	assert.equal(preferVolumeAnchor(null, other), other);
	const a = anchorToActualVolume({
		weeks: [week(0, 40_000, 20_000, true, []), fullWeek(1, '2026-06-08')],
	});
	assert.ok(a);
	assert.equal(preferVolumeAnchor(a, other), a.changes);
});
