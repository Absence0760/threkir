import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { nextRace, planRaces } from './plan_races';

const plan = {
	end_date: '2027-06-13',
	goal_distance_m: 91000,
	goal_time_seconds: 39600,
	trimmed_at: null
};
const twoOceans = {
	id: 'w-two-oceans',
	scheduled_date: '2027-04-04',
	kind: 'race',
	race_name: 'Two Oceans Ultra',
	race_priority: 'B',
	target_distance_m: 56000,
	target_duration_seconds: 23400
};
const comrades = {
	id: 'w-comrades',
	scheduled_date: '2027-06-13',
	kind: 'race',
	race_name: 'Comrades',
	race_priority: null,
	target_distance_m: null,
	target_duration_seconds: null
};
const parkrun = {
	id: 'w-parkrun',
	scheduled_date: '2027-02-06',
	kind: 'race',
	race_name: 'parkrun',
	race_priority: null,
	target_distance_m: 5000,
	target_duration_seconds: null
};
const longRun = {
	id: 'w-long',
	scheduled_date: '2027-03-06',
	kind: 'long',
	target_distance_m: 42195,
	target_duration_seconds: null
};

test('planRaces: a plan with no race workouts yields one A race at its end date from the plan goal', () => {
	assert.deepEqual(planRaces(plan, [longRun]), [
		{
			date: '2027-06-13',
			name: null,
			priority: 'A',
			distanceM: 91000,
			goalTimeSec: 39600,
			workoutId: null
		}
	]);
});

test('planRaces: a race workout on the end date with no priority is A and inherits the plan goal', () => {
	assert.deepEqual(planRaces(plan, [comrades]), [
		{
			date: '2027-06-13',
			name: 'Comrades',
			priority: 'A',
			distanceM: 91000,
			goalTimeSec: 39600,
			workoutId: 'w-comrades'
		}
	]);
});

test('planRaces: a mid-plan race workout with priority B keeps its own name, distance and goal time', () => {
	const races = planRaces(plan, [twoOceans]);
	assert.equal(races.length, 2);
	assert.deepEqual(races[0], {
		date: '2027-04-04',
		name: 'Two Oceans Ultra',
		priority: 'B',
		distanceM: 56000,
		goalTimeSec: 23400,
		workoutId: 'w-two-oceans'
	});
	assert.equal(races[1].workoutId, null);
	assert.equal(races[1].priority, 'A');
});

test('planRaces: a mid-plan race workout with no priority defaults to C', () => {
	const races = planRaces(plan, [parkrun]);
	assert.equal(races[0].workoutId, 'w-parkrun');
	assert.equal(races[0].priority, 'C');
	assert.equal(races[0].distanceM, 5000);
	assert.equal(races[0].goalTimeSec, null);
});

test('planRaces: races are sorted by date and the end-date A race is not duplicated', () => {
	const races = planRaces(plan, [comrades, longRun, twoOceans, parkrun]);
	assert.deepEqual(
		races.map((r) => [r.workoutId, r.priority]),
		[
			['w-parkrun', 'C'],
			['w-two-oceans', 'B'],
			['w-comrades', 'A']
		]
	);
});

test('nextRace: returns the first race on or after today, counting race day itself', () => {
	const races = planRaces(plan, [comrades, twoOceans, parkrun]);
	assert.equal(nextRace(races, '2026-11-16')?.workoutId, 'w-parkrun');
	assert.equal(nextRace(races, '2027-02-07')?.workoutId, 'w-two-oceans');
	assert.equal(nextRace(races, '2027-04-04')?.workoutId, 'w-two-oceans');
	assert.equal(nextRace(races, '2027-04-05')?.workoutId, 'w-comrades');
	assert.equal(nextRace(races, '2027-06-13')?.workoutId, 'w-comrades');
});

test('planRaces: a trimmed plan has no implicit end-date race', () => {
	const trimmed = { ...plan, trimmed_at: '2027-03-01T09:00:00+00:00' };
	const races = planRaces(trimmed, [twoOceans, longRun]);
	assert.deepEqual(
		races.map((r) => r.workoutId),
		['w-two-oceans']
	);
	assert.deepEqual(planRaces(trimmed, [longRun]), []);
	const withRace = planRaces(trimmed, [comrades]);
	assert.equal(withRace.length, 1);
	assert.equal(withRace[0].workoutId, 'w-comrades');
	assert.equal(withRace[0].priority, 'A');
});

test('nextRace: returns null after the last race', () => {
	const races = planRaces(plan, [comrades, twoOceans]);
	assert.equal(nextRace(races, '2027-06-14'), null);
	assert.equal(nextRace([], '2027-01-01'), null);
});

const houstonPlan = {
	end_date: '2027-01-23',
	goal_distance_m: 42195,
	goal_time_seconds: 14400,
	trimmed_at: null
};
const houston = {
	id: 'w-houston',
	scheduled_date: '2027-01-17',
	kind: 'race',
	race_name: null,
	race_priority: null,
	target_distance_m: 42195,
	target_duration_seconds: null
};

test('planRaces: a race-week race before an end date with no race is the A goal race, not a C race plus a synthetic A (#1294)', () => {
	assert.deepEqual(planRaces(houstonPlan, [houston]), [
		{
			date: '2027-01-17',
			name: null,
			priority: 'A',
			distanceM: 42195,
			goalTimeSec: 14400,
			workoutId: 'w-houston'
		}
	]);
});

test('planRaces: a race-week race marked B or C keeps its priority and the end date keeps its synthetic A race', () => {
	const races = planRaces(houstonPlan, [{ ...houston, race_priority: 'C' }]);
	assert.deepEqual(
		races.map((r) => [r.workoutId, r.priority, r.date]),
		[
			['w-houston', 'C', '2027-01-17'],
			[null, 'A', '2027-01-23']
		]
	);
});

test('planRaces: only the final seven days count as race week, and a trimmed plan promotes nothing', () => {
	const weekBefore = planRaces(houstonPlan, [{ ...houston, scheduled_date: '2027-01-16' }]);
	assert.deepEqual(
		weekBefore.map((r) => [r.workoutId, r.priority]),
		[
			['w-houston', 'C'],
			[null, 'A']
		]
	);
	const trimmed = planRaces({ ...houstonPlan, trimmed_at: '2027-01-23T09:00:00+00:00' }, [houston]);
	assert.deepEqual(
		trimmed.map((r) => [r.workoutId, r.priority]),
		[['w-houston', 'C']]
	);
});
