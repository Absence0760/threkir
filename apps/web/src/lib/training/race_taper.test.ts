import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import type { PlanRace } from './plan_races';
import { raceTaperAdjustments, raceTaperPatch, raceTaperProposals, type RaceTaperWorkout } from './race_taper';

function race(date: string, priority: 'A' | 'B' | 'C', distanceM: number | null): PlanRace {
	return { date, name: `race-${date}`, priority, distanceM, goalTimeSec: null, workoutId: `r-${date}` };
}

function wo(id: string, scheduledDate: string, kind: string, targetDistanceM: number | null, extra: Partial<RaceTaperWorkout> = {}): RaceTaperWorkout {
	return { id, scheduledDate, kind, targetDistanceM, targetDurationSeconds: null, structure: null, notes: null, phase: 'build', completed: false, skipped: false, taperApplied: false, ...extra };
}

const TODAY = '2027-03-01';
// A road B race: every case below that is not about ultras pins the road
// windows, which the ultra rules must leave exactly as they were.
const springHalf = race('2027-04-04', 'B', 21097.5);
const twoOceans = race('2027-04-04', 'B', 56000);

function summary(changes: ReturnType<typeof raceTaperProposals>) {
	return changes.map((c) => [c.workoutId, c.reason, c.toKind, c.toMetres, c.clearsPace]);
}

test('raceTaperProposals: a B race eases the 6 days before it and runs quality easy', () => {
	const changes = raceTaperProposals({
		workouts: [
			wo('w-long', '2027-03-28', 'long', 30000),
			wo('w-int', '2027-03-29', 'interval', 10000),
			wo('w-easy', '2027-03-31', 'easy', 8000)
		],
		races: [springHalf],
		today: TODAY
	});
	assert.deepEqual(summary(changes), [
		['w-int', 'pre_race', 'easy', 6500, true],
		['w-easy', 'pre_race', 'easy', 5200, false]
	]);
	assert.equal(changes[0].raceDate, '2027-04-04');
	assert.equal(changes[0].racePriority, 'B');
	assert.equal(changes[0].raceName, 'race-2027-04-04');
});

test('raceTaperProposals: the 2 days before a B race carry only a shakeout capped at 5 km', () => {
	const changes = raceTaperProposals({
		workouts: [
			wo('w-tempo', '2027-04-02', 'tempo', 12000),
			wo('w-easy', '2027-04-03', 'easy', 8000),
			wo('w-walk', '2027-04-03', 'walk_run', null)
		],
		races: [springHalf],
		today: TODAY
	});
	assert.deepEqual(summary(changes), [
		['w-tempo', 'shakeout', 'easy', 5000, true],
		['w-easy', 'shakeout', 'easy', 4000, false]
	]);
});

test('raceTaperProposals: recovery after a B race lasts one day per 3 km raced, 4 to 7 days', () => {
	const after = (r: PlanRace, days: string[]) =>
		raceTaperProposals({
			workouts: days.map((d) => wo(`w-${d}`, d, 'tempo', 8000)),
			races: [r],
			today: TODAY
		}).map((c) => c.scheduledDate);
	assert.deepEqual(after(springHalf, ['2027-04-11', '2027-04-12']), ['2027-04-11']);
	assert.deepEqual(after(race('2027-04-04', 'B', 10000), ['2027-04-08', '2027-04-09']), [
		'2027-04-08'
	]);
	assert.deepEqual(after(race('2027-04-04', 'B', null), ['2027-04-09', '2027-04-10']), [
		'2027-04-09'
	]);
});

test('raceTaperProposals: recovery caps the long run at 75% and runs quality easy', () => {
	const changes = raceTaperProposals({
		workouts: [
			wo('w-int', '2027-04-06', 'interval', 10000),
			wo('w-long', '2027-04-07', 'long', 24000),
			wo('w-easy', '2027-04-08', 'easy', 8000)
		],
		races: [springHalf],
		today: TODAY
	});
	assert.deepEqual(summary(changes), [
		['w-int', 'post_race', 'easy', 10000, true],
		['w-long', 'post_race', 'long', 18000, false]
	]);
});

test('raceTaperProposals: a C race eases 3 days before and 2 days after', () => {
	const parkrun = race('2027-03-20', 'C', 5000);
	const changes = raceTaperProposals({
		workouts: [
			wo('w-a', '2027-03-16', 'interval', 10000),
			wo('w-b', '2027-03-17', 'interval', 10000),
			wo('w-c', '2027-03-22', 'tempo', 9000),
			wo('w-d', '2027-03-23', 'tempo', 9000)
		],
		races: [parkrun],
		today: TODAY
	});
	assert.deepEqual(summary(changes), [
		['w-b', 'pre_race', 'easy', 8000, true],
		['w-c', 'post_race', 'easy', 9000, true]
	]);
	assert.equal(changes[0].racePriority, 'C');
});

test('raceTaperProposals: done, skipped, past, rest, race and A-taper workouts are never touched', () => {
	const changes = raceTaperProposals({
		workouts: [
			wo('w-done', '2027-03-30', 'tempo', 10000, { completed: true }),
			wo('w-skip', '2027-03-30', 'tempo', 10000, { skipped: true }),
			wo('w-rest', '2027-03-31', 'rest', null),
			wo('w-race', '2027-04-04', 'race', 56000),
			wo('w-other-race', '2027-04-02', 'race', 5000),
			wo('w-taper', '2027-04-01', 'tempo', 10000, { phase: 'taper' }),
			wo('w-past', '2027-03-30', 'tempo', 10000)
		],
		races: [springHalf],
		today: '2027-03-31'
	});
	assert.deepEqual(changes, []);
});

test('raceTaperProposals: a race already run, or an A race, gets no window', () => {
	const workouts = [wo('w-int', '2027-04-02', 'interval', 10000), wo('w-tmp', '2027-04-06', 'tempo', 8000)];
	assert.deepEqual(raceTaperProposals({ workouts, races: [springHalf], today: '2027-04-04' }), []);
	assert.deepEqual(
		raceTaperProposals({ workouts, races: [race('2027-04-04', 'A', 42195)], today: TODAY }),
		[]
	);
});

test('raceTaperProposals: overlapping windows take the stronger rule', () => {
	const changes = raceTaperProposals({
		workouts: [wo('w-x', '2027-04-02', 'tempo', 12000), wo('w-y', '2027-03-31', 'easy', 10000)],
		races: [race('2027-03-30', 'C', 5000), race('2027-03-31', 'C', 5000), springHalf],
		today: TODAY
	});
	assert.deepEqual(summary(changes), [
		['w-y', 'pre_race', 'easy', 6500, false],
		['w-x', 'shakeout', 'easy', 5000, true]
	]);
	assert.deepEqual(
		changes.map((c) => [c.workoutId, c.raceDate]),
		[
			['w-y', '2027-04-04'],
			['w-x', '2027-04-04']
		]
	);
});

test('raceTaperPatch: writes only the columns that change', () => {
	const [quality, easy] = raceTaperProposals({
		workouts: [wo('w-int', '2027-03-30', 'interval', 10000), wo('w-easy', '2027-03-31', 'easy', 8000)],
		races: [springHalf],
		today: TODAY
	});
	assert.deepEqual(raceTaperPatch(quality), {
		kind: 'easy',
		target_distance_m: 6500,
		target_pace_sec_per_km: null,
		target_pace_tolerance_sec: null,
		structure: null
	});
	assert.deepEqual(raceTaperPatch(easy), { target_distance_m: 5200 });
});

test('raceTaperAdjustments: stamps every applied change so it is not proposed again', () => {
	const changes = raceTaperProposals({
		workouts: [wo('w-easy', '2027-03-31', 'easy', 8000)],
		races: [springHalf],
		today: TODAY
	});
	assert.deepEqual(raceTaperAdjustments(changes, '2027-03-02T08:00:00.000Z'), [
		{ id: 'w-easy', target_distance_m: 5200, race_taper_applied_at: '2027-03-02T08:00:00.000Z' }
	]);
});

test('raceTaperProposals: a workout an applied taper already eased is not cut again', () => {
	const workouts = [wo('w-int', '2027-03-30', 'interval', 10000), wo('w-easy', '2027-03-31', 'easy', 8000)];
	const first = raceTaperProposals({ workouts, races: [springHalf], today: TODAY });
	const applied = workouts.map((w) => {
		const c = first.find((x) => x.workoutId === w.id)!;
		return { ...w, kind: c.toKind, targetDistanceM: c.toMetres, taperApplied: true };
	});
	assert.deepEqual(summary(raceTaperProposals({ workouts: applied, races: [springHalf], today: TODAY })), []);
	assert.deepEqual(
		summary(raceTaperProposals({ workouts: applied.map((w) => ({ ...w, taperApplied: false })), races: [springHalf], today: TODAY })),
		[
			['w-int', 'pre_race', 'easy', 4225, false],
			['w-easy', 'pre_race', 'easy', 3380, false]
		]
	);
});

test('raceTaperProposals: duration shrinks by the factor the distance moved', () => {
	const changes = raceTaperProposals({
		workouts: [
			wo('w-easy', '2027-03-30', 'easy', 8000, { targetDurationSeconds: 2400 }),
			wo('w-timed', '2027-03-31', 'easy', null, { targetDurationSeconds: 3600 }),
			wo('w-tempo', '2027-04-02', 'tempo', 12000, { targetDurationSeconds: 3600 })
		],
		races: [springHalf],
		today: TODAY
	});
	assert.deepEqual(
		changes.map((c) => [c.workoutId, c.toMetres, c.fromDurationS, c.toDurationS]),
		[
			['w-easy', 5200, 2400, 1560],
			['w-timed', null, 3600, 2340],
			// The shakeout's 5 km cap is the factor: 5000 / 12000 of 3600 s.
			['w-tempo', 5000, 3600, 1500]
		]
	);
	assert.deepEqual(raceTaperPatch(changes[1]), { target_duration_seconds: 2340 });
});

test('raceTaperProposals: a walk/run day loses repeats with the session, and the notes that described them', () => {
	const intervals = {
		warmup: { duration_s: 300, pace: 'easy' },
		repeats: { count: 8, duration_s: 90, recovery_duration_s: 120, recovery_pace: 'walk' },
		cooldown: { duration_s: 300, pace: 'easy' }
	};
	const continuous = {
		warmup: { duration_s: 300, pace: 'easy' },
		repeats: { count: 1, duration_s: 1800, recovery_pace: 'walk' },
		cooldown: { duration_s: 300, pace: 'easy' }
	};
	const [wr, grad] = raceTaperProposals({
		workouts: [
			wo('w-wr', '2027-03-30', 'walk_run', 4000, {
				targetDurationSeconds: 2160,
				structure: intervals,
				notes: 'Walk 5 min, then run 90s / walk 120s × 8, walk 5 min.'
			}),
			wo('w-grad', '2027-03-31', 'walk_run', 5000, { targetDurationSeconds: 2400, structure: continuous })
		],
		races: [springHalf],
		today: TODAY
	});
	// 8 repeats × 0.65 = 5.2 → 5; 300 + 5 × 90 + 4 × 120 + 300 = 1530 s.
	assert.deepEqual(raceTaperPatch(wr), {
		target_distance_m: 2600,
		target_duration_seconds: 1530,
		structure: { ...intervals, repeats: { ...intervals.repeats, count: 5 } },
		notes: null
	});
	// One continuous run: 1800 s × 0.65 = 1170 s; 300 + 1170 + 300 = 1770 s.
	assert.deepEqual(raceTaperPatch(grad), {
		target_distance_m: 3250,
		target_duration_seconds: 1770,
		structure: { ...continuous, repeats: { ...continuous.repeats, duration_s: 1170 } }
	});
});

test('raceTaperProposals: a session whose kind changes loses the notes and structure that described it', () => {
	const changes = raceTaperProposals({
		workouts: [
			wo('w-int', '2027-03-29', 'interval', 10000, { notes: '6x800 at 5K pace', structure: { repeats: { count: 6 } } }),
			wo('w-long', '2027-03-30', 'long', 20000, { notes: 'Last 5 km at marathon pace', structure: { steady: { distance_m: 5000 } } }),
			wo('w-easy', '2027-03-31', 'easy', 8000, { notes: 'Flat route' })
		],
		races: [springHalf],
		today: TODAY
	});
	assert.deepEqual(raceTaperPatch(changes[0]), {
		kind: 'easy',
		target_distance_m: 6500,
		target_pace_sec_per_km: null,
		target_pace_tolerance_sec: null,
		structure: null,
		notes: null
	});
	assert.deepEqual(raceTaperPatch(changes[1]), {
		kind: 'easy',
		target_distance_m: 13000,
		structure: null,
		notes: null
	});
	// Same kind, only shorter: the runner's own note still fits.
	assert.deepEqual(raceTaperPatch(changes[2]), { target_distance_m: 5200 });
});

test('raceTaperProposals: recovery after an ultra B race adds a day per 2 km past the marathon, up to 21', () => {
	const after = (r: PlanRace, days: string[]) =>
		raceTaperProposals({
			workouts: days.map((d) => wo(`w-${d}`, d, 'tempo', 8000)),
			races: [r],
			today: TODAY
		}).map((c) => c.scheduledDate);
	// Two Oceans: 7 + (56 - 42.195) / 2 = 13.9 -> 14 days.
	assert.deepEqual(after(twoOceans, ['2027-04-18', '2027-04-19']), ['2027-04-18']);
	// A 90 km race reaches the 21-day ceiling; 100 miles stays there.
	assert.deepEqual(after(race('2027-04-04', 'B', 90000), ['2027-04-25', '2027-04-26']), ['2027-04-25']);
	assert.deepEqual(after(race('2027-04-04', 'B', 160934.4), ['2027-04-25', '2027-04-26']), ['2027-04-25']);
	// Continuous at the marathon: the marathon and a 43 km race both take 7.
	assert.deepEqual(after(race('2027-04-04', 'B', 42195), ['2027-04-11', '2027-04-12']), ['2027-04-11']);
	assert.deepEqual(after(race('2027-04-04', 'B', 43000), ['2027-04-11', '2027-04-12']), ['2027-04-11']);
	// A C race stays at 2 days at any distance.
	assert.deepEqual(after(race('2027-04-04', 'C', 56000), ['2027-04-06', '2027-04-07']), ['2027-04-06']);
});

test('raceTaperProposals: an ultra B race eases the 8 days before it, a road B race 6', () => {
	const before = (r: PlanRace) =>
		raceTaperProposals({
			workouts: [
				wo('w-9', '2027-03-26', 'easy', 8000),
				wo('w-8', '2027-03-27', 'long', 30000, { targetDurationSeconds: 3 * 3600 }),
				wo('w-7', '2027-03-28', 'long', 30000)
			],
			races: [r],
			today: TODAY
		}).map((c) => [c.workoutId, c.reason, c.toKind, c.toMetres, c.toDurationS]);
	assert.deepEqual(before(twoOceans), [
		['w-8', 'pre_race', 'easy', 19500, 7020],
		['w-7', 'pre_race', 'easy', 19500, null]
	]);
	assert.deepEqual(before(springHalf), []);
});
