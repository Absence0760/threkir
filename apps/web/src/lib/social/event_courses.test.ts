import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	COURSE_NAME_MAX,
	finishMethodBadge,
	groupResultsByCourse,
	hostTimeEditPatch,
	needsCoursePick,
	planCourseSave,
	sortCourses,
	validateCourseDrafts,
	type EventCourse
} from './event_courses';

function course(id: string, name: string, sort_order: number, extra: Partial<EventCourse> = {}): EventCourse {
	return { id, event_id: 'e1', route_id: null, name, distance_m: null, sort_order, ...extra };
}

test('sortCourses orders by sort_order, then name, without mutating the input', () => {
	const input = [course('b', 'Half', 1), course('a', 'Full', 0), course('c', 'Arrow', 1)];
	const out = sortCourses(input);
	assert.deepEqual(out.map((c) => c.id), ['a', 'c', 'b']);
	assert.equal(input[0].id, 'b');
});

test('needsCoursePick asks only when there is a choice', () => {
	assert.equal(needsCoursePick([]), false);
	assert.equal(needsCoursePick([course('a', 'Only', 0)]), false);
	assert.equal(needsCoursePick([course('a', '10K', 0), course('b', '5K', 1)]), true);
});

test('validateCourseDrafts names the first offending row', () => {
	const ok = { name: '10K', routeId: null, distanceM: 10000 };
	assert.equal(validateCourseDrafts([ok]), null);
	assert.equal(validateCourseDrafts([]), null);
	assert.deepEqual(validateCourseDrafts([ok, { ...ok, name: '   ' }]), { index: 1, error: 'name_required' });
	assert.deepEqual(
		validateCourseDrafts([{ ...ok, name: 'x'.repeat(COURSE_NAME_MAX + 1) }]),
		{ index: 0, error: 'name_too_long' }
	);
	assert.equal(validateCourseDrafts([{ ...ok, name: 'x'.repeat(COURSE_NAME_MAX) }]), null);
	assert.deepEqual(validateCourseDrafts([ok, { ...ok, name: ' 10k ' }]), { index: 1, error: 'name_duplicate' });
	for (const bad of [0, -5, Number.NaN, Number.POSITIVE_INFINITY, 1_000_001]) {
		assert.deepEqual(validateCourseDrafts([{ ...ok, distanceM: bad }]), { index: 0, error: 'distance_invalid' }, String(bad));
	}
	assert.equal(validateCourseDrafts([{ ...ok, distanceM: null }]), null);
	assert.equal(validateCourseDrafts([{ ...ok, distanceM: 1_000_000 }]), null);
});

test('planCourseSave inserts new rows, updates changed ones, deletes dropped ones', () => {
	const existing = [
		course('a', '10K', 0, { distance_m: 10000 }),
		course('b', '5K', 1, { distance_m: 5000 }),
		course('c', 'Kids', 2)
	];
	const plan = planCourseSave(existing, [
		{ id: 'b', name: '5K', routeId: null, distanceM: 5000 },
		{ id: 'a', name: '10K', routeId: null, distanceM: 10000 },
		{ name: ' Mile ', routeId: 'r9', distanceM: 1609 }
	]);
	assert.deepEqual(plan.inserts, [{ name: 'Mile', route_id: 'r9', distance_m: 1609, sort_order: 2 }]);
	assert.deepEqual(plan.updates, [
		{ id: 'b', patch: { name: '5K', route_id: null, distance_m: 5000, sort_order: 0 } },
		{ id: 'a', patch: { name: '10K', route_id: null, distance_m: 10000, sort_order: 1 } }
	]);
	assert.deepEqual(plan.deletes, ['c']);
});

test('planCourseSave writes nothing for an unchanged list', () => {
	const existing = [course('a', '10K', 0, { route_id: 'r1', distance_m: 10000 })];
	const plan = planCourseSave(existing, [{ id: 'a', name: '10K', routeId: 'r1', distanceM: 10000 }]);
	assert.deepEqual(plan, { inserts: [], updates: [], deletes: [] });
});

test('planCourseSave treats an unknown id as a new course', () => {
	const plan = planCourseSave([], [{ id: 'gone', name: '10K', routeId: null, distanceM: null }]);
	assert.equal(plan.inserts.length, 1);
	assert.equal(plan.updates.length, 0);
});

test('groupResultsByCourse gives every course a board, in course order, keeping rank order', () => {
	const courses = [course('k5', '5K', 1), course('k10', '10K', 0)];
	const results = [
		{ id: 'r1', course_id: 'k5' },
		{ id: 'r2', course_id: 'k10' },
		{ id: 'r3', course_id: 'k5' }
	];
	const boards = groupResultsByCourse(results, courses);
	assert.deepEqual(
		boards.map((b) => [b.course?.id ?? null, b.results.map((r) => r.id)]),
		[
			['k10', ['r2']],
			['k5', ['r1', 'r3']]
		]
	);
});

test('groupResultsByCourse keeps an empty course board and adds a trailing board for orphans', () => {
	const courses = [course('k10', '10K', 0), course('k5', '5K', 1)];
	const boards = groupResultsByCourse(
		[
			{ id: 'r1', course_id: 'k10' },
			{ id: 'r2', course_id: null },
			{ id: 'r3', course_id: 'deleted' }
		],
		courses
	);
	assert.deepEqual(
		boards.map((b) => [b.course?.id ?? null, b.results.map((r) => r.id)]),
		[
			['k10', ['r1']],
			['k5', []],
			[null, ['r2', 'r3']]
		]
	);
});

test('groupResultsByCourse on an event with no courses is the one board it always was', () => {
	const results = [{ id: 'r1', course_id: null }, { id: 'r2', course_id: null }];
	const boards = groupResultsByCourse(results, []);
	assert.equal(boards.length, 1);
	assert.equal(boards[0].course, null);
	assert.deepEqual(boards[0].results.map((r) => r.id), ['r1', 'r2']);
});

test('finishMethodBadge flags only times the finish rule did not measure', () => {
	assert.equal(finishMethodBadge('manual'), 'manual');
	assert.equal(finishMethodBadge('host'), 'host');
	assert.equal(finishMethodBadge('auto'), null);
	assert.equal(finishMethodBadge(null), null);
});

test('hostTimeEditPatch moves the gun time with the ranked time only on a gun-started race', () => {
	assert.deepEqual(hostTimeEditPatch(2450.4, true), { duration_s: 2450, gun_time_s: 2450 });
	assert.deepEqual(hostTimeEditPatch(2450, false), { duration_s: 2450 });
	assert.deepEqual(hostTimeEditPatch(-3, true), { duration_s: 0, gun_time_s: 0 });
});
