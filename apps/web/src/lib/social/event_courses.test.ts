import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
	COURSE_NAME_MAX,
	CourseSaveError,
	applyCourseSave,
	finishMethodBadge,
	groupResultsByCourse,
	hostTimeEditPatch,
	needsCoursePick,
	planCourseSave,
	sortCourses,
	validateCourseDrafts,
	type CourseSavePlan,
	type CourseWriteResult,
	type CourseWriter,
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

test('hostTimeEditPatch moves the gun time with the ranked time only on a row that has one', () => {
	assert.deepEqual(hostTimeEditPatch(2450.4, 2600), { duration_s: 2450, gun_time_s: 2450 });
	assert.deepEqual(hostTimeEditPatch(-3, 2600), { duration_s: 0, gun_time_s: 0 });
	assert.deepEqual(hostTimeEditPatch(2450, 0), { duration_s: 2450, gun_time_s: 2450 });
});

test('hostTimeEditPatch never gives a gun time to a row that never had one', () => {
	const patch = hostTimeEditPatch(2450, null);
	assert.deepEqual(patch, { duration_s: 2450 });
	assert.equal('gun_time_s' in patch, false, 'an absent key leaves the column alone; a key would write it');
});

test('the host time edit passes the edited row\'s own gun time, not the race session', () => {
	const page = readFileSync(resolve('src/routes/clubs/[slug]/events/[id]/+page.svelte'), 'utf-8');
	const calls = [...page.matchAll(/hostTimeEditPatch\(([^)]*)\)/g)].map((c) => c[1]);
	assert.deepEqual(calls, ['seconds, editingResult.gun_time_s']);
});

type Call = { op: 'delete' | 'update' | 'insert'; arg: unknown };

/// A stand-in store: every call is logged, and `answer` decides what each
/// write returns (by default, every row asked for, no error).
function fakeWriter(answer: (c: Call, asked: number) => CourseWriteResult = (_c, n) => ({ error: null, rows: n })) {
	const calls: Call[] = [];
	const writer: CourseWriter = {
		delete: async (ids) => {
			const c: Call = { op: 'delete', arg: ids };
			calls.push(c);
			return answer(c, ids.length);
		},
		update: async (id, patch) => {
			const c: Call = { op: 'update', arg: { id, patch } };
			calls.push(c);
			return answer(c, 1);
		},
		insert: async (rows) => {
			const c: Call = { op: 'insert', arg: rows };
			calls.push(c);
			return answer(c, rows.length);
		}
	};
	return { writer, calls };
}

const fullPlan: CourseSavePlan = {
	deletes: ['c', 'd'],
	updates: [
		{ id: 'b', patch: { name: '5K', route_id: null, distance_m: 5000, sort_order: 0 } },
		{ id: 'a', patch: { name: '10K', route_id: null, distance_m: 10000, sort_order: 1 } }
	],
	inserts: [
		{ name: 'Mile', route_id: null, distance_m: 1609, sort_order: 2 },
		{ name: 'Kids', route_id: null, distance_m: 1000, sort_order: 3 }
	]
};

test('applyCourseSave deletes, then updates, then inserts every new course in one statement', async () => {
	const { writer, calls } = fakeWriter();
	await applyCourseSave(fullPlan, writer);
	assert.deepEqual(
		calls.map((c) => c.op),
		['delete', 'update', 'update', 'insert'],
		'an insert is the one write a retry cannot repeat safely, so it must be last and single'
	);
	assert.deepEqual(calls[0].arg, ['c', 'd']);
	assert.deepEqual(calls[3].arg, fullPlan.inserts);
});

test('applyCourseSave issues no statement for an empty plan', async () => {
	const { writer, calls } = fakeWriter();
	await applyCourseSave({ deletes: [], updates: [], inserts: [] }, writer);
	assert.deepEqual(calls, []);
});

for (const step of ['delete', 'update', 'insert'] as const) {
	test(`a failed ${step} surfaces with PostgREST's message and nothing after it runs`, async () => {
		const { writer, calls } = fakeWriter((c, n) =>
			c.op === step ? { error: { message: `${step} denied by policy` }, rows: 0 } : { error: null, rows: n }
		);
		await assert.rejects(
			applyCourseSave(fullPlan, writer),
			(e) => e instanceof CourseSaveError && e.step === step && e.message === `${step} denied by policy`
		);
		const order = ['delete', 'update', 'insert'];
		assert.ok(
			calls.every((c) => order.indexOf(c.op) <= order.indexOf(step)),
			`a write ran after the failed ${step}: ${calls.map((c) => c.op).join(', ')}`
		);
		if (step !== 'insert') {
			assert.equal(calls.some((c) => c.op === 'insert'), false, 'a failure before the insert must insert nothing');
		}
	});
}

test('a delete RLS filtered to fewer rows than asked is a failure, not a success', async () => {
	const { writer, calls } = fakeWriter((c, n) => (c.op === 'delete' ? { error: null, rows: 1 } : { error: null, rows: n }));
	await assert.rejects(
		applyCourseSave(fullPlan, writer),
		(e) => e instanceof CourseSaveError && e.step === 'delete' && /1 of 2/.test(e.message)
	);
	assert.deepEqual(calls.map((c) => c.op), ['delete']);
});

test('an update that matched no row stops the save before any insert', async () => {
	const { writer, calls } = fakeWriter((c, n) => (c.op === 'update' ? { error: null, rows: 0 } : { error: null, rows: n }));
	await assert.rejects(applyCourseSave(fullPlan, writer), (e) => e instanceof CourseSaveError && e.step === 'update');
	assert.deepEqual(calls.map((c) => c.op), ['delete', 'update']);
});

test('an error with no message still says which write failed', async () => {
	const { writer } = fakeWriter(() => ({ error: {}, rows: 0 }));
	await assert.rejects(applyCourseSave(fullPlan, writer), (e) => e instanceof Error && e.message === 'course delete failed');
});

test('a retry after a part-way failure, planned against the re-read list, repeats no delete and inserts once', async () => {
	const stored = [course('a', '10K', 0), course('b', '5K', 1), course('c', 'Kids', 2)];
	const drafts = [
		{ id: 'a', name: '10K', routeId: null, distanceM: null },
		{ id: 'b', name: 'Five', routeId: null, distanceM: null },
		{ name: 'Mile', routeId: null, distanceM: 1609 }
	];
	const first = fakeWriter((c, n) => (c.op === 'update' ? { error: { message: 'boom' }, rows: 0 } : { error: null, rows: n }));
	await assert.rejects(applyCourseSave(planCourseSave(stored, drafts), first.writer));
	assert.deepEqual(first.calls.map((c) => c.op), ['delete', 'update']);

	const reread = stored.filter((c) => c.id !== 'c');
	const second = fakeWriter();
	await applyCourseSave(planCourseSave(reread, drafts), second.writer);
	assert.deepEqual(second.calls.map((c) => c.op), ['update', 'insert']);
	assert.deepEqual(second.calls[1].arg, [{ name: 'Mile', route_id: null, distance_m: 1609, sort_order: 2 }]);
});

test('saveEventCourses routes every write through applyCourseSave and returns ids for the row check', () => {
	const src = readFileSync(resolve('src/lib/core/data.ts'), 'utf-8');
	const start = src.indexOf('export async function saveEventCourses');
	assert.ok(start >= 0, 'saveEventCourses moved or was renamed');
	const body = src.slice(start, src.indexOf('\nexport ', start + 1));
	assert.match(body, /applyCourseSave\(planCourseSave\(existing, drafts\)/);
	assert.equal((body.match(/\.select\('id'\)/g) ?? []).length, 3, 'delete, update and insert must each return their ids');
	assert.doesNotMatch(body, /if \(error\) throw error/, 'a raw PostgREST error is not an Error, so the editor would show [object Object]');
});
