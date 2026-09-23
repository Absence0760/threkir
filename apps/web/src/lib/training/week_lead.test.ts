import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	nextPlanSession,
	plannedDistanceForWeek,
	recentWeeklyAverage,
	weekLead,
	type LeadPlanWorkout,
} from './week_lead';

// 2026-06-10 is a Wednesday; the Monday-start week runs 06-08..06-14.
const WED = new Date(2026, 5, 10, 12, 0, 0);
const MON = new Date(2026, 5, 8, 0, 0, 0);

function at(y: number, mo: number, d: number, h = 9): string {
	return new Date(y, mo - 1, d, h, 0, 0).toISOString();
}

function wo(date: string, over: Partial<LeadPlanWorkout> = {}): LeadPlanWorkout {
	return {
		scheduled_date: date,
		kind: 'easy',
		target_distance_m: 5000,
		manually_completed: false,
		completed_run_id: null,
		skipped_at: null,
		...over,
	};
}

test('weekLead: sums only this calendar week and counts every activity in it', () => {
	const lead = weekLead({
		activities: [
			{ started_at: at(2026, 6, 7), distance_m: 9000 },
			{ started_at: at(2026, 6, 8), distance_m: 5000 },
			{ started_at: at(2026, 6, 10), distance_m: 3000 },
		],
		planWorkouts: null,
		weekStart: 'monday',
		now: WED,
	});
	assert.equal(lead.distanceM, 8000);
	assert.equal(lead.count, 2);
});

test('weekLead: a sunday-start week takes in the sunday a monday-start week leaves out', () => {
	const lead = weekLead({
		activities: [{ started_at: at(2026, 6, 7), distance_m: 9000 }],
		planWorkouts: null,
		weekStart: 'sunday',
		now: WED,
	});
	assert.equal(lead.distanceM, 9000);
});

test('weekLead: a workout marked done without a run counts toward the week, a linked one does not', () => {
	const lead = weekLead({
		activities: [{ started_at: at(2026, 6, 9), distance_m: 4000 }],
		planWorkouts: [
			wo('2026-06-08', { manually_completed: true, target_distance_m: 6000 }),
			wo('2026-06-09', { manually_completed: true, completed_run_id: 'r1' }),
			wo('2026-06-12', { manually_completed: true }),
		],
		weekStart: 'monday',
		now: WED,
	});
	assert.equal(lead.distanceM, 10_000);
	assert.equal(lead.count, 2);
});

test('weekLead: compares against the plan when the plan puts distance in this week', () => {
	const lead = weekLead({
		activities: [{ started_at: at(2026, 5, 20), distance_m: 20_000 }],
		planWorkouts: [wo('2026-06-09'), wo('2026-06-11', { target_distance_m: 8000 }), wo('2026-06-16')],
		weekStart: 'monday',
		now: WED,
	});
	assert.deepEqual(lead.comparison, { kind: 'plan', targetM: 13_000 });
});

test('weekLead: falls back to the recent average when the plan has nothing this week', () => {
	const lead = weekLead({
		activities: [
			{ started_at: at(2026, 5, 12), distance_m: 8000 },
			{ started_at: at(2026, 6, 2), distance_m: 12_000 },
		],
		planWorkouts: [wo('2026-06-20')],
		weekStart: 'monday',
		now: WED,
	});
	assert.deepEqual(lead.comparison, { kind: 'average', averageM: 5000, weeks: 4 });
});

test('weekLead: no yardstick when there is no plan distance and no recent activity', () => {
	const lead = weekLead({
		activities: [{ started_at: at(2025, 1, 5), distance_m: 5000 }],
		planWorkouts: null,
		weekStart: 'monday',
		now: WED,
	});
	assert.equal(lead.comparison, null);
	assert.equal(lead.next, null);
	assert.equal(lead.nextInDays, null);
});

test('recentWeeklyAverage: a history shorter than the window averages over the weeks it has', () => {
	const avg = recentWeeklyAverage([{ started_at: at(2026, 6, 2), distance_m: 6000 }], MON);
	assert.deepEqual(avg, { averageM: 6000, weeks: 1 });
	const two = recentWeeklyAverage(
		[
			{ started_at: at(2026, 5, 26), distance_m: 4000 },
			{ started_at: at(2026, 6, 3), distance_m: 6000 },
		],
		MON,
	);
	assert.deepEqual(two, { averageM: 5000, weeks: 2 });
});

test('recentWeeklyAverage: activity only in the current week is no history yet', () => {
	assert.equal(recentWeeklyAverage([{ started_at: at(2026, 6, 9), distance_m: 5000 }], MON), null);
	assert.equal(recentWeeklyAverage([], MON), null);
});

test('plannedDistanceForWeek: ignores rest days and workouts outside the calendar week', () => {
	const total = plannedDistanceForWeek(
		[
			wo('2026-06-07'),
			wo('2026-06-08', { target_distance_m: 3000 }),
			wo('2026-06-10', { kind: 'rest', target_distance_m: 9000 }),
			wo('2026-06-14', { target_distance_m: null }),
			wo('2026-06-14', { target_distance_m: 12_000 }),
			wo('2026-06-15'),
		],
		MON,
	);
	assert.equal(total, 15_000);
});

test('nextPlanSession: the earliest open, non-rest session from today on', () => {
	const next = nextPlanSession(
		[
			wo('2026-06-14', { kind: 'long' }),
			wo('2026-06-09'),
			wo('2026-06-10', { manually_completed: true }),
			wo('2026-06-11', { kind: 'rest' }),
			wo('2026-06-12', { skipped_at: '2026-06-09T10:00:00Z' }),
			wo('2026-06-13', { kind: 'tempo' }),
		],
		'2026-06-10',
	);
	assert.equal(next?.scheduled_date, '2026-06-13');
	assert.equal(next?.kind, 'tempo');
});

test('nextPlanSession: today counts while it is still open', () => {
	assert.equal(nextPlanSession([wo('2026-06-12'), wo('2026-06-10')], '2026-06-10')?.scheduled_date, '2026-06-10');
	assert.equal(nextPlanSession([wo('2026-06-01')], '2026-06-10'), null);
});

test('weekLead: nextInDays counts calendar days to the next session', () => {
	const lead = weekLead({
		activities: [],
		planWorkouts: [wo('2026-06-11')],
		weekStart: 'monday',
		now: WED,
	});
	assert.equal(lead.next?.scheduled_date, '2026-06-11');
	assert.equal(lead.nextInDays, 1);
});
