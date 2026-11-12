import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	PLAN_CHANGE_STATUSES,
	parseChangeList,
	parsePlanChangeStatus,
	planChangeIds,
	planChangeLines,
	type PlanChangeWeekRow,
	type PlanChangeWorkoutRow,
} from './plan_change.ts';

const rows: PlanChangeWorkoutRow[] = [
	{ id: 'w2', scheduled_date: '2027-11-17', kind: 'tempo', target_distance_m: 8000, target_duration_seconds: null, skipped_at: null },
	{ id: 'w1', scheduled_date: '2027-11-16', kind: 'easy', target_distance_m: 10000, target_duration_seconds: 3600, skipped_at: null },
	{ id: 'w3', scheduled_date: '2027-11-18', kind: 'rest', target_distance_m: null, target_duration_seconds: null, skipped_at: null },
];
const weeks: PlanChangeWeekRow[] = [
	{ id: 'k1', week_index: 1, target_volume_m: 30000 },
	{ id: 'k0', week_index: 0, target_volume_m: 28000 },
];

test('the status vocabulary is the CHECK set, and anything else reads as unknown', () => {
	assert.deepEqual([...PLAN_CHANGE_STATUSES], ['pending', 'approved', 'declined', 'withdrawn', 'overridden']);
	for (const s of PLAN_CHANGE_STATUSES) assert.equal(parsePlanChangeStatus(s), s);
	assert.equal(parsePlanChangeStatus('applied'), null);
	assert.equal(parsePlanChangeStatus(null), null);
});

test('only objects with a string id are changes', () => {
	assert.deepEqual(parseChangeList(null), []);
	assert.deepEqual(parseChangeList({ id: 'x' }), []);
	assert.deepEqual(parseChangeList([{ id: 'a' }, { id: 3 }, null, ['id'], 'id', { id: 'b', skip: true }]), [
		{ id: 'a' },
		{ id: 'b', skip: true },
	]);
});

test('ids are listed in stored order', () => {
	assert.deepEqual(planChangeIds([{ id: 'w2' }, { id: 'w1' }], [{ id: 'k0', target_volume_m: 1 }]), {
		workoutIds: ['w2', 'w1'],
		weekIds: ['k0'],
	});
});

test('a scaled workout keeps what the change does not name', () => {
	const r = planChangeLines([{ id: 'w1', target_distance_m: 9000 }], [], rows, weeks);
	assert.equal(r.workouts.length, 1);
	assert.deepEqual(r.workouts[0].before, {
		scheduledDate: '2027-11-16',
		kind: 'easy',
		distanceM: 10000,
		durationS: 3600,
		skipped: false,
	});
	assert.deepEqual(r.workouts[0].after, {
		scheduledDate: '2027-11-16',
		kind: 'easy',
		distanceM: 9000,
		durationS: 3600,
		skipped: false,
	});
});

test('an ease to recovery, a move and a skip each land on their own line, sorted by the current day', () => {
	const r = planChangeLines(
		[
			{ id: 'w3', scheduled_date: '2027-11-19' },
			{ id: 'w2', kind: 'recovery', target_distance_m: 5000, target_pace_sec_per_km: null },
			{ id: 'w1', skip: true },
		],
		[],
		rows,
		weeks,
	);
	assert.deepEqual(
		r.workouts.map((l) => l.workoutId),
		['w1', 'w2', 'w3'],
	);
	assert.equal(r.workouts[0].after.skipped, true);
	assert.equal(r.workouts[1].after.kind, 'recovery');
	assert.equal(r.workouts[1].after.distanceM, 5000);
	assert.equal(r.workouts[2].after.scheduledDate, '2027-11-19');
	assert.equal(r.unreadable, 0);
});

test('a malformed field keeps the current value rather than inventing one', () => {
	const r = planChangeLines([{ id: 'w1', target_distance_m: 'lots', kind: 7, skip: 'yes' }], [], rows, weeks);
	assert.deepEqual(r.workouts[0].after, r.workouts[0].before);
});

test('an explicit null clears the target', () => {
	const r = planChangeLines([{ id: 'w1', target_duration_seconds: null }], [], rows, weeks);
	assert.equal(r.workouts[0].after.durationS, null);
});

test('week targets are listed by week, and unreadable rows are counted, not shown', () => {
	const r = planChangeLines(
		[{ id: 'gone', target_distance_m: 1 }],
		[
			{ id: 'k1', target_volume_m: 27000 },
			{ id: 'k0', target_volume_m: 25200 },
			{ id: 'k9', target_volume_m: 1 },
		],
		rows,
		weeks,
	);
	assert.deepEqual(r.workouts, []);
	assert.deepEqual(r.weeks, [
		{ weekId: 'k0', weekIndex: 0, beforeM: 28000, afterM: 25200 },
		{ weekId: 'k1', weekIndex: 1, beforeM: 30000, afterM: 27000 },
	]);
	assert.equal(r.unreadable, 2);
});
