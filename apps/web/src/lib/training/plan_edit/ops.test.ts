// Unit tests for the AI plan-edit trust boundary. Run via
// `npx tsx --test apps/web/src/lib/training/plan_edit/ops.test.ts`.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	MAX_PLAN_EDIT_OPS,
	MAX_SCALE_FACTOR,
	MIN_SCALE_FACTOR,
	buildPlanEditContext,
	describePlanForEdit,
	isoWeekday,
	validatePlanEditOps,
	weekWindow,
} from './ops';
import { TODAY, fixture } from './test_fixture';

function ctx() {
	return buildPlanEditContext(fixture(), TODAY);
}

function validate(operations: unknown, extra: Record<string, unknown> = {}) {
	return validatePlanEditOps({ operations, ...extra }, ctx());
}

test('references are handed out in date order over the open weeks only', () => {
	const c = ctx();
	assert.equal(c.workoutByRef.get('W1'), 'a-int');
	assert.equal(c.workoutByRef.get('W4'), 'a-long');
	assert.equal(c.workoutByRef.get('W15'), 'd-race');
	assert.equal(c.workoutByRef.size, 15);

	const later = buildPlanEditContext(fixture(), '2026-10-20');
	// Week 1 ended on the 18th, so none of it is shown.
	assert.equal(later.refByWorkout.has('a-long'), false);
	assert.equal(later.workoutByRef.get('W1'), 'b-int');
});

test('a move inside the workout\'s own week is accepted', () => {
	const r = validate([{ op: 'move_workout', workout: 'W9', date: '2026-10-24' }]);
	assert.deepEqual(r.ops, [{ op: 'move_workout', workoutId: 'b-long', date: '2026-10-24' }]);
	assert.equal(r.dropped, 0);
	assert.deepEqual(r.notes, []);
});

test('references are read case- and space-insensitively', () => {
	const r = validate([{ op: 'skip_workout', workout: ' w6 ' }]);
	assert.deepEqual(r.ops, [{ op: 'skip_workout', workoutId: 'b-easy' }]);
});

test('a move out of its week, into the past, onto a bad date or to the same day is dropped', () => {
	for (const op of [
		{ op: 'move_workout', workout: 'W9', date: '2026-10-26' }, // next week
		{ op: 'move_workout', workout: 'W3', date: '2026-10-14' }, // past
		{ op: 'move_workout', workout: 'W9', date: '2026-10-32' }, // not a date
		{ op: 'move_workout', workout: 'W9', date: 'Sunday' },
		{ op: 'move_workout', workout: 'W9', date: '2026-10-25' }, // same day
		{ op: 'move_workout', workout: 'W9' },
	]) {
		const r = validate([op]);
		assert.deepEqual(r.ops, [], JSON.stringify(op));
		assert.equal(r.dropped, 1);
		assert.deepEqual(r.notes, ['op_dropped']);
	}
});

test('a workout that is done, skipped, past, a race or a rest day cannot be targeted', () => {
	const snapshot = fixture();
	snapshot.workouts.find((w) => w.id === 'b-easy')!.skipped_at = '2026-10-14T10:00:00Z';
	const c = buildPlanEditContext(snapshot, TODAY);
	for (const ref of ['W1', 'W6', 'W7', 'W15']) {
		const r = validatePlanEditOps({ operations: [{ op: 'skip_workout', workout: ref }] }, c);
		assert.deepEqual(r.ops, [], ref);
	}
});

test('an unknown reference, a raw id or an unknown op is dropped', () => {
	const r = validate([
		{ op: 'skip_workout', workout: 'W99' },
		{ op: 'skip_workout', workout: 'b-easy' },
		{ op: 'add_workout', workout: 'W6' },
		null,
		'skip W6',
	]);
	assert.deepEqual(r.ops, []);
	assert.equal(r.dropped, 5);
});

test('a swap needs two editable workouts on different days of the same week', () => {
	assert.deepEqual(validate([{ op: 'swap_days', workout: 'W5', other_workout: 'W9' }]).ops, [
		{ op: 'swap_days', workoutId: 'b-int', otherWorkoutId: 'b-long' },
	]);
	for (const pair of [
		['W5', 'W5'],
		['W4', 'W5'], // across weeks
		['W1', 'W3'], // W1 is done
		['W5', 'W7'], // W7 is a rest day
	]) {
		assert.deepEqual(
			validate([{ op: 'swap_days', workout: pair[0], other_workout: pair[1] }]).ops,
			[],
			pair.join('/'),
		);
	}
});

test('a workout can be the target of one operation only', () => {
	const r = validate([
		{ op: 'move_workout', workout: 'W9', date: '2026-10-24' },
		{ op: 'skip_workout', workout: 'W9' },
		{ op: 'swap_days', workout: 'W8', other_workout: 'W9' },
	]);
	assert.equal(r.ops.length, 1);
	assert.equal(r.dropped, 2);
});

test('scale_week takes the 1-based week number the runner sees and clamps the factor into the band', () => {
	assert.deepEqual(validate([{ op: 'scale_week', week: 2, factor: 0.8 }]).ops, [
		{ op: 'scale_week', weekIndex: 1, factor: 0.8 },
	]);
	const high = validate([{ op: 'scale_week', week: 2, factor: 1.5 }]);
	assert.deepEqual(high.ops, [{ op: 'scale_week', weekIndex: 1, factor: MAX_SCALE_FACTOR }]);
	assert.deepEqual(high.notes, ['factor_clamped']);
	const low = validate([{ op: 'scale_week', week: 2, factor: 0.1 }]);
	assert.deepEqual(low.ops, [{ op: 'scale_week', weekIndex: 1, factor: MIN_SCALE_FACTOR }]);
});

test('a scale-up never reaches the taper, and a no-op factor is dropped', () => {
	const taper = validate([{ op: 'scale_week', week: 4, factor: 1.1 }]);
	assert.deepEqual(taper.ops, []);
	assert.ok(taper.notes.includes('factor_clamped'));
	assert.deepEqual(validate([{ op: 'scale_week', week: 4, factor: 0.9 }]).ops, [
		{ op: 'scale_week', weekIndex: 3, factor: 0.9 },
	]);
	for (const factor of [1, 0, -2, Number.NaN, '0.8']) {
		assert.deepEqual(validate([{ op: 'scale_week', week: 2, factor }]).ops, [], String(factor));
	}
});

test('a week op needs a real, open week with something left to change, once', () => {
	for (const week of [0, 5, 2.5, '2']) {
		assert.deepEqual(validate([{ op: 'mark_recovery', week }]).ops, [], String(week));
	}
	const r = validate([
		{ op: 'mark_recovery', week: 3 },
		{ op: 'scale_week', week: 3, factor: 0.8 },
	]);
	assert.deepEqual(r.ops, [{ op: 'mark_recovery', weekIndex: 2 }]);
	assert.equal(r.dropped, 1);

	const past = buildPlanEditContext(fixture(), '2026-10-20');
	assert.deepEqual(
		validatePlanEditOps({ operations: [{ op: 'mark_recovery', week: 1 }] }, past).ops,
		[],
	);
});

test('operations past the cap are dropped and named', () => {
	const many = Array.from({ length: MAX_PLAN_EDIT_OPS + 3 }, (_, i) => ({
		op: 'skip_workout',
		workout: `W${i + 2}`,
	}));
	const r = validate(many);
	assert.ok(r.ops.length <= MAX_PLAN_EDIT_OPS);
	assert.ok(r.notes.includes('too_many_ops'));
});

test('a malformed payload yields no operations rather than throwing', () => {
	for (const raw of [null, undefined, 'x', 42, [], { operations: 'all' }]) {
		const r = validatePlanEditOps(raw, ctx());
		assert.deepEqual(r.ops, []);
	}
});

test('the model saying the request is out of scope is carried as a note', () => {
	const r = validate([], { unsupported: true });
	assert.deepEqual(r.notes, ['unsupported']);
});

test('weekWindow and isoWeekday date a plan week the way the plan page does', () => {
	assert.deepEqual(weekWindow('2026-10-12', 1), { start: '2026-10-19', end: '2026-10-25' });
	assert.equal(isoWeekday('2026-10-25'), 'Sun');
	assert.equal(isoWeekday('2026-10-12'), 'Mon');
	assert.equal(isoWeekday('nope'), '');
});

test('the model sees references, days, kinds and sizes, and no ids, notes or paces', () => {
	const text = describePlanForEdit(ctx());
	assert.match(text, /^Week 1 \(build, Mon 2026-10-12 to Sun 2026-10-18, 40\.0 km planned\)$/m);
	assert.match(text, /^ {2}W1 Tue 2026-10-13 interval 8\.0 km \[done\]$/m);
	assert.match(text, /^ {2}W9 Sun 2026-10-25 long 20\.0 km$/m);
	assert.match(text, /^ {2}W15 Sun 2026-11-08 race 16\.0 km \[fixed\]$/m);
	assert.doesNotMatch(text, /b-long|a-int|270|pace/);
});
