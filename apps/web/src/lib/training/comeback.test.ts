import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	LAYOFF_MAX_DAYS,
	LAYOFF_MIN_DAYS,
	RETURN_WEEK_SHARE,
	RETURN_WEEKLY_GROWTH,
	capReturnRamp,
	comebackLoad,
	returningFromBreak,
	shouldSurfaceComeback,
} from './comeback';
import { CHRONIC_WINDOW_WEEKS, MIN_ACTIVE_WEEKS } from './plan_ramp';
import { selfLoad, shouldSurfaceSelfLoad } from './self_load';
import { kLayoffResetDays } from './training_load';

const NOW = Date.parse('2026-08-14T12:00:00Z');
const DAY_MS = 86_400_000;

function run(daysAgo: number, distanceM: number, activityType = 'run') {
	return {
		started_at: new Date(NOW - daysAgo * DAY_MS).toISOString(),
		distance_m: distanceM,
		activity_type: activityType,
	};
}

/// A runner who trained 40 km a week for four weeks, took `layoffDays` off,
/// and has just logged `thisWeekM` in the last seven days.
function comebackRunner(layoffDays: number, thisWeekM: number, baseWeeklyM = 40_000) {
	const lastBefore = 1 + layoffDays;
	return [
		run(1, thisWeekM),
		run(lastBefore, baseWeeklyM),
		run(lastBefore + 7, baseWeeklyM),
		run(lastBefore + 14, baseWeeklyM),
		run(lastBefore + 21, baseWeeklyM),
	];
}

test('the layoff threshold is the fitness-reset one, not a second number', () => {
	assert.equal(LAYOFF_MIN_DAYS, kLayoffResetDays);
});

test('a gentle first week back is graded easing_in', () => {
	const load = comebackLoad(comebackRunner(70, 12_000), NOW);
	assert.equal(load.verdict, 'easing_in');
	assert.equal(load.thisWeekM, 12_000);
	assert.equal(load.preLayoffWeeklyM, 160_000 / CHRONIC_WINDOW_WEEKS);
	assert.ok(Math.abs(load.share - 0.3) < 1e-9);
	assert.equal(load.layoffDays, 70);
	assert.equal(load.layoffWeeks, 10);
});

test('a big first week back is graded steep', () => {
	const load = comebackLoad(comebackRunner(70, 36_000), NOW);
	assert.equal(load.verdict, 'steep');
	assert.ok(Math.abs(load.share - 0.9) < 1e-9);
});

test('the steep threshold is exclusive — exactly half the old base still eases in', () => {
	const half = RETURN_WEEK_SHARE * 40_000;
	assert.equal(comebackLoad(comebackRunner(70, half), NOW).verdict, 'easing_in');
	assert.equal(comebackLoad(comebackRunner(70, half + 1), NOW).verdict, 'steep');
});

test('layoff weeks round to nearest so a break is never understated', () => {
	// 32 days is 4.57 weeks — the case that separates rounding from flooring,
	// which would report 4 and undersell the break by most of a week.
	assert.equal(comebackLoad(comebackRunner(32, 12_000), NOW).layoffWeeks, 5);
	assert.equal(comebackLoad(comebackRunner(45, 12_000), NOW).layoffWeeks, 6);
});

test('a rest week shorter than the layoff threshold is not a comeback', () => {
	const load = comebackLoad(comebackRunner(LAYOFF_MIN_DAYS - 2, 30_000), NOW);
	assert.equal(load.verdict, 'insufficient');
});

test('a break long enough to reset fitness is a comeback', () => {
	const load = comebackLoad(comebackRunner(LAYOFF_MIN_DAYS, 30_000), NOW);
	assert.notEqual(load.verdict, 'insufficient');
});

test('a base too stale to anchor against says nothing rather than reassuring', () => {
	const stale = comebackLoad(comebackRunner(LAYOFF_MAX_DAYS + 1, 30_000), NOW);
	assert.equal(stale.verdict, 'insufficient');
	assert.equal(stale.share, 0);
	assert.equal(stale.layoffDays, 0);
	const fresh = comebackLoad(comebackRunner(LAYOFF_MAX_DAYS, 30_000), NOW);
	assert.notEqual(fresh.verdict, 'insufficient');
});

test('a single run before the break is not a base to come back to', () => {
	const load = comebackLoad([run(1, 30_000), run(71, 40_000)], NOW);
	assert.equal(load.verdict, 'insufficient');
});

test('the pre-break base needs MIN_ACTIVE_WEEKS of its own windows', () => {
	const twoWeeks = [run(1, 30_000), run(71, 40_000), run(78, 40_000)];
	assert.equal(comebackLoad(twoWeeks, NOW).verdict, 'insufficient');
	assert.equal(MIN_ACTIVE_WEEKS, 3);
	const threeWeeks = [...twoWeeks, run(85, 40_000)];
	assert.notEqual(comebackLoad(threeWeeks, NOW).verdict, 'insufficient');
});

test('a week with no running is not graded as a gentle return', () => {
	const idle = comebackRunner(70, 12_000).slice(1);
	assert.equal(comebackLoad(idle, NOW).verdict, 'insufficient');
});

test('a runner who never stopped is not on a comeback', () => {
	const steady = [run(1, 40_000), run(8, 40_000), run(15, 40_000), run(22, 40_000)];
	assert.equal(comebackLoad(steady, NOW).verdict, 'insufficient');
});

test('an empty history says nothing', () => {
	assert.equal(comebackLoad([], NOW).verdict, 'insufficient');
});

test('a run stamped in the future does not inflate the break it appears to open', () => {
	// A clock 40 days ahead puts today's run in the future; the hole between it
	// and the runner's last real session reads as 70 days unclamped, and 30 —
	// the break they actually took — once the stamp is pulled back to now.
	const runs = [run(-40, 10_000), run(30, 40_000), run(37, 40_000), run(44, 40_000), run(51, 40_000)];
	const load = comebackLoad(runs, NOW);
	assert.equal(load.layoffDays, 30);
	assert.equal(load.thisWeekM, 10_000);
});

test('a skewed stamp grades identically to an honest one', () => {
	const base = [run(60, 40_000), run(67, 40_000), run(74, 40_000), run(81, 40_000)];
	const skewed = comebackLoad([run(-100, 8_000), ...base], NOW);
	const honest = comebackLoad([run(0, 8_000), ...base], NOW);
	assert.deepEqual(skewed, honest);
	assert.equal(honest.layoffDays, 60);
});

test('the two load cards are mutually exclusive by construction', () => {
	const cases = [
		comebackRunner(70, 36_000),
		comebackRunner(70, 12_000),
		comebackRunner(LAYOFF_MIN_DAYS - 2, 30_000),
		[run(1, 40_000), run(8, 40_000), run(15, 40_000), run(22, 40_000)],
		// Back for three consecutive weeks: the ratio can carry the question
		// again, so the comeback card must stand down.
		[run(1, 30_000), run(8, 20_000), run(15, 10_000), run(80, 40_000), run(87, 40_000), run(94, 40_000)],
		[],
	];
	for (const runs of cases) {
		const ratio = shouldSurfaceSelfLoad(selfLoad(runs, NOW));
		const comeback = shouldSurfaceComeback(comebackLoad(runs, NOW));
		assert.ok(!(ratio && comeback), 'both load cards surfaced for the same history');
	}
});

test('a returned runner with three active weeks is handed back to the ratio card', () => {
	const runs = [
		run(1, 30_000),
		run(8, 20_000),
		run(15, 10_000),
		run(80, 40_000),
		run(87, 40_000),
		run(94, 40_000),
	];
	assert.equal(comebackLoad(runs, NOW).verdict, 'insufficient');
	assert.ok(shouldSurfaceSelfLoad(selfLoad(runs, NOW)));
});

test('the most recent break is the one graded, not an older one', () => {
	const runs = [
		run(1, 30_000),
		run(41, 40_000),
		run(48, 40_000),
		run(55, 40_000),
		run(62, 40_000),
		// An older, longer break sits behind a full pre-break base.
		run(400, 90_000),
	];
	const load = comebackLoad(runs, NOW);
	assert.equal(load.layoffDays, 40);
	assert.equal(load.preLayoffWeeklyM, 160_000 / CHRONIC_WINDOW_WEEKS);
});

test('cycling is not running volume on either side of the break', () => {
	const runs = [
		run(1, 12_000),
		run(2, 60_000, 'cycle'),
		run(71, 40_000),
		run(78, 40_000),
		run(85, 40_000),
		run(86, 100_000, 'cycle'),
	];
	const load = comebackLoad(runs, NOW);
	assert.equal(load.thisWeekM, 12_000);
	assert.equal(load.preLayoffWeeklyM, 120_000 / CHRONIC_WINDOW_WEEKS);
});

test('unparseable and non-positive rows are dropped rather than read as a break', () => {
	const runs = [
		run(1, 12_000),
		{ started_at: 'not-a-date', distance_m: 50_000, activity_type: 'run' },
		{ started_at: new Date(NOW - 35 * DAY_MS).toISOString(), distance_m: 0, activity_type: 'run' },
		run(71, 40_000),
		run(78, 40_000),
		run(85, 40_000),
	];
	const load = comebackLoad(runs, NOW);
	assert.equal(load.verdict, 'easing_in');
	assert.equal(load.layoffDays, 70);
});

test('shouldSurfaceComeback narrows to the verdicts the card has copy for', () => {
	const load = comebackLoad(comebackRunner(70, 36_000), NOW);
	assert.ok(shouldSurfaceComeback(load));
	if (shouldSurfaceComeback(load)) {
		const verdict: 'easing_in' | 'steep' = load.verdict;
		assert.equal(verdict, 'steep');
	}
	assert.equal(shouldSurfaceComeback(comebackLoad([], NOW)), false);
});

/// Four 40 km weeks ending `lastRunDaysAgo` days ago, and nothing since.
function openBreakRunner(lastRunDaysAgo: number, baseWeeklyM = 40_000) {
	return [0, 7, 14, 21].map((w) => run(lastRunDaysAgo + w, baseWeeklyM));
}

test('returningFromBreak reads a break that is still open, before the first run back', () => {
	const r = returningFromBreak(openBreakRunner(60), NOW);
	assert.ok(r);
	assert.equal(r.layoffDays, 60);
	assert.equal(r.layoffWeeks, 9);
	assert.equal(r.preLayoffWeeklyM, 40_000);
	assert.equal(r.openingCapM, 40_000 * RETURN_WEEK_SHARE);
	// comebackLoad has nothing to grade until the runner runs again.
	assert.equal(comebackLoad(openBreakRunner(60), NOW).verdict, 'insufficient');
});

test('returningFromBreak agrees with comebackLoad on a break the runner has ended', () => {
	const runs = comebackRunner(60, 5_000);
	const r = returningFromBreak(runs, NOW);
	assert.ok(r);
	assert.equal(r.layoffDays, comebackLoad(runs, NOW).layoffDays);
	assert.equal(r.preLayoffWeeklyM, comebackLoad(runs, NOW).preLayoffWeeklyM);
});

test('returningFromBreak is null for a runner training consistently now', () => {
	const runs = [1, 8, 15, 22].map((d) => run(d, 30_000));
	assert.equal(returningFromBreak(runs, NOW), null);
});

test('returningFromBreak is null with no running history at all', () => {
	assert.equal(returningFromBreak([], NOW), null);
	assert.equal(returningFromBreak([run(3, 20_000, 'cycle')], NOW), null);
});

test('returningFromBreak is null for a break too old to anchor against', () => {
	assert.equal(returningFromBreak(openBreakRunner(LAYOFF_MAX_DAYS + 1), NOW), null);
	assert.ok(returningFromBreak(openBreakRunner(LAYOFF_MAX_DAYS), NOW));
});

test('returningFromBreak is null for a break that ended more than four weeks ago', () => {
	// Four 40 km weeks ending 380 days ago, then a run a fortnight for the last
	// 100 days: the break ended long enough ago that its base no longer
	// describes the runner, however sporadic the running since.
	const since = [2, 16, 30, 44, 58, 72, 86, 100].map((d) => run(d, 5_000));
	assert.equal(returningFromBreak([...since, ...openBreakRunner(380)], NOW), null);
	// The same break ending 20 days ago still counts.
	const recent = [2, 20].map((d) => run(d, 5_000));
	assert.ok(returningFromBreak([...recent, ...openBreakRunner(200)], NOW));
});

test('returningFromBreak is null when the pre-break base is a single run', () => {
	assert.equal(returningFromBreak([run(60, 40_000)], NOW), null);
});

function rampWorkout(kind: string, metres: number | null) {
	return {
		kind,
		target_distance_m: metres,
		target_duration_seconds: null as number | null,
		target_pace_sec_per_km: kind === 'rest' ? null : 300,
		target_pace_tolerance_sec: kind === 'rest' ? null : 8,
		structure: kind === 'interval' ? { repeats: { count: 5 } } : null,
		notes: kind === 'interval' ? '5 x 1 km' : null,
	};
}
function rampWeek(index: number, workouts: ReturnType<typeof rampWorkout>[]) {
	return {
		week_index: index,
		target_volume_m: workouts.reduce((s, w) => s + (w.target_distance_m ?? 0), 0),
		workouts,
	};
}

test('capReturnRamp caps week 1, lets the next grow 10%, and stops at the first week that fits', () => {
	const weeks = [
		rampWeek(0, [rampWorkout('long', 12_000), rampWorkout('rest', null), rampWorkout('interval', 8_000)]),
		rampWeek(1, [rampWorkout('long', 12_000), rampWorkout('rest', null), rampWorkout('easy', 8_000)]),
		rampWeek(2, [rampWorkout('long', 10_000), rampWorkout('race', 5_000)]),
	];
	const capped = capReturnRamp(weeks, 10_000, 420);
	// Week 1: 20 km against a 10 km cap, so every session halves.
	assert.equal(capped[0].target_volume_m, 10_000);
	assert.equal(capped[0].workouts[0].target_distance_m, 6_000);
	assert.equal(capped[0].workouts[2].target_distance_m, 4_000);
	// The interval session is an easy run at the easy pace now.
	assert.equal(capped[0].workouts[2].kind, 'easy');
	assert.equal(capped[0].workouts[2].target_pace_sec_per_km, 420);
	assert.equal(capped[0].workouts[2].target_pace_tolerance_sec, 30);
	assert.equal(capped[0].workouts[2].structure, null);
	assert.equal(capped[0].workouts[2].notes, null);
	assert.equal(capped[0].workouts[1], weeks[0].workouts[1]);
	// Week 2: capped at 10 km x 1.1 = 11 km, to the nearest 100 m per session.
	assert.equal(10_000 * RETURN_WEEKLY_GROWTH, 11_000);
	assert.equal(capped[1].workouts[0].target_distance_m, 6_600);
	assert.equal(capped[1].workouts[2].target_distance_m, 4_400);
	assert.equal(capped[1].target_volume_m, 11_000);
	// Week 3: 10 km of running fits its 12.1 km cap (the race is not counted),
	// so the climb ends there and the week is exactly as generated.
	assert.equal(capped[2], weeks[2]);
	// The input is untouched.
	assert.equal(weeks[0].target_volume_m, 20_000);
	assert.equal(weeks[0].workouts[2].kind, 'interval');
});

test('capReturnRamp keeps climbing past a step-back week that fits, up to the last week over its cap', () => {
	// 40 / 44 / 36 / 48 km against caps of 35 / 38.5 / 42.35 / 46.585 km. The
	// step-back third week fits, but the fourth is over its cap, so the climb
	// runs through both: the third keeps its distances and loses its intervals,
	// and the fourth scales by 46.585 / 48 to the nearest 100 m.
	const weeks = [40_000, 44_000, 36_000, 48_000].map((m, i) =>
		rampWeek(i, [rampWorkout('long', m - 8_000), rampWorkout('interval', 8_000)]),
	);
	const capped = capReturnRamp(weeks, 35_000, 420);
	assert.equal(capped[0].workouts[1].kind, 'easy');
	assert.equal(capped[1].workouts[1].kind, 'easy');
	assert.equal(capped[2].workouts[0].target_distance_m, 28_000);
	assert.equal(capped[2].workouts[1].target_distance_m, 8_000);
	assert.equal(capped[2].workouts[1].kind, 'easy');
	assert.equal(capped[3].workouts[0].target_distance_m, 38_800);
	assert.equal(capped[3].workouts[1].target_distance_m, 7_800);
	assert.equal(capped[3].workouts[1].kind, 'easy');
	assert.equal(weeks[3].workouts[1].kind, 'interval');
});

test('capReturnRamp drops sessions the cap would take under 3 km to rest, shortest first', () => {
	// 20 km over four runs against a 6 km cap: scaling alone would ask for a
	// 900 m run. The 3, 4 and 5 km runs drop in turn and the long run takes
	// the whole 6 km.
	const weeks = [
		rampWeek(0, [
			rampWorkout('long', 8_000),
			rampWorkout('easy', 5_000),
			rampWorkout('easy', 4_000),
			rampWorkout('easy', 3_000),
		]),
	];
	const [week] = capReturnRamp(weeks, 6_000, 420);
	assert.equal(week.workouts[0].target_distance_m, 6_000);
	for (const dropped of week.workouts.slice(1)) {
		assert.equal(dropped.kind, 'rest');
		assert.equal(dropped.target_distance_m, null);
		assert.equal(dropped.target_pace_sec_per_km, null);
	}
	assert.equal(week.target_volume_m, 6_000);
});

test('capReturnRamp labels an easy run it shortens under 4 km a recovery run', () => {
	// Two 6 km easy runs against a 7 km cap become two 3.5 km runs.
	const [week] = capReturnRamp([rampWeek(0, [rampWorkout('easy', 6_000), rampWorkout('easy', 6_000)])], 7_000, 420);
	assert.deepEqual(
		week.workouts.map((w) => [w.kind, w.target_distance_m]),
		[
			['recovery', 3_500],
			['recovery', 3_500],
		],
	);
});

test('capReturnRamp leaves a week under its cap, and every week for a cap that is not positive', () => {
	const weeks = [rampWeek(0, [rampWorkout('easy', 5_000)])];
	assert.equal(capReturnRamp(weeks, 10_000, 420)[0], weeks[0]);
	assert.equal(capReturnRamp(weeks, 0, 420), weeks);
	assert.equal(capReturnRamp(weeks, Number.NaN, 420), weeks);
});
