import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import type { PlanRace } from './plan_races';
import { raceTaperPatch, raceTaperProposals, type RaceTaperWorkout } from './race_taper';

function race(date: string, priority: 'A' | 'B' | 'C', distanceM: number | null): PlanRace {
	return { date, name: `race-${date}`, priority, distanceM, goalTimeSec: null, workoutId: `r-${date}` };
}

function wo(id: string, scheduledDate: string, kind: string, targetDistanceM: number | null, extra: Partial<RaceTaperWorkout> = {}): RaceTaperWorkout {
	return { id, scheduledDate, kind, targetDistanceM, phase: 'build', completed: false, skipped: false, ...extra };
}

const TODAY = '2027-03-01';
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
		races: [twoOceans],
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
		races: [twoOceans],
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
	assert.deepEqual(after(twoOceans, ['2027-04-11', '2027-04-12']), ['2027-04-11']);
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
		races: [twoOceans],
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
		races: [twoOceans],
		today: '2027-03-31'
	});
	assert.deepEqual(changes, []);
});

test('raceTaperProposals: a race already run, or an A race, gets no window', () => {
	const workouts = [wo('w-int', '2027-04-02', 'interval', 10000), wo('w-tmp', '2027-04-06', 'tempo', 8000)];
	assert.deepEqual(raceTaperProposals({ workouts, races: [twoOceans], today: '2027-04-04' }), []);
	assert.deepEqual(
		raceTaperProposals({ workouts, races: [race('2027-04-04', 'A', 42195)], today: TODAY }),
		[]
	);
});

test('raceTaperProposals: overlapping windows take the stronger rule', () => {
	const changes = raceTaperProposals({
		workouts: [wo('w-x', '2027-04-02', 'tempo', 12000), wo('w-y', '2027-03-31', 'easy', 10000)],
		races: [race('2027-03-30', 'C', 5000), race('2027-03-31', 'C', 5000), twoOceans],
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
		races: [twoOceans],
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
