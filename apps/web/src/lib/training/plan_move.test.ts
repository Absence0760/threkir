// Unit tests for the days a planned workout can be moved to.
// Run via `npx tsx --test apps/web/src/lib/training/plan_move.test.ts`.
// Dart twin: apps/mobile_android/test/plan_move_test.dart (same cases).

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { canDisplaceForMove, workoutMoveDays, type MovableWorkout } from './plan_move';

// Week 1 (from Monday 2031-03-10) of a plan starting Monday 2031-03-03,
// stored the way the generator writes it: a row on every day.
function row(id: string, date: string, kind: string, extra: Partial<MovableWorkout> = {}): MovableWorkout {
	return { id, week_id: 'wk1', scheduled_date: date, kind, completed_run_id: null, manually_completed: false, ...extra };
}
const week = [
	row('mon', '2031-03-10', 'rest'),
	row('tue', '2031-03-11', 'tempo'),
	row('wed', '2031-03-12', 'easy', { manually_completed: true }),
	row('thu', '2031-03-13', 'race'),
];

test('every other day of the week is offered, with its occupant', () => {
	const days = workoutMoveDays('2031-03-03', '2031-03-20', 1, week[1], week, '2031-03-01');
	assert.deepEqual(
		days.map((d) => [d.date, d.occupant?.id ?? null]),
		[
			['2031-03-10', 'mon'],
			['2031-03-14', null],
			['2031-03-15', null],
			['2031-03-16', null],
		],
	);
});

test('a completed workout or a race is never displaced', () => {
	const days = workoutMoveDays('2031-03-03', '2031-03-20', 1, week[1], week, '2031-03-01');
	assert.equal(days.some((d) => d.date === '2031-03-12' || d.date === '2031-03-13'), false);
	assert.equal(canDisplaceForMove(week[0]), true);
	assert.equal(canDisplaceForMove(week[2]), false);
	assert.equal(canDisplaceForMove(week[3]), false);
	assert.equal(canDisplaceForMove(row('linked', '2031-03-10', 'easy', { completed_run_id: 'run-1' })), false);
});

test('days past the plan end or before today are not offered', () => {
	const days = workoutMoveDays('2031-03-03', '2031-03-14', 1, week[1], week, '2031-03-11');
	assert.deepEqual(
		days.map((d) => d.date),
		['2031-03-14'],
	);
});

test('a row in another week never counts as an occupant', () => {
	const rows = [row('w0-mon', '2031-03-03', 'easy', { week_id: 'wk0' }), row('stray', '2031-03-05', 'long')];
	const days = workoutMoveDays('2031-03-03', '2031-03-20', 0, rows[0], rows, '2031-03-01');
	assert.deepEqual(
		days.map((d) => [d.date, d.occupant?.id ?? null]),
		[
			['2031-03-04', null],
			['2031-03-05', null],
			['2031-03-06', null],
			['2031-03-07', null],
			['2031-03-08', null],
			['2031-03-09', null],
		],
	);
});

test('a completed workout keeps its day', () => {
	assert.deepEqual(workoutMoveDays('2031-03-03', '2031-03-20', 1, week[2], week, '2031-03-01'), []);
});
