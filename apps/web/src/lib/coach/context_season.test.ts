// Issue #1213: the Coach reads a runner's season — the current plan and the
// plans chained after it — bounded by the same week window as one plan.
// Run with `npx tsx --test src/lib/coach/context_season.test.ts` from apps/web.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { AI_DISCLOSURE_CURRENT_VERSION } from '../core/ai_disclosure';
import {
	buildContext,
	coachPlanWeekWindow,
	COACH_PLAN_WEEKS_CAP,
	type CoachPlanScope,
	type CoachProfileRow,
} from './context';

const USER = 'user-1';
const DAY_MS = 86_400_000;

type Row = Record<string, unknown>;

/// PostgREST-shaped stub that honours eq / in / numeric gte / order / limit,
/// and records every read so a test can say which plans were queried.
function stubSupabase(tables: Record<string, Row[]>, reads: Array<{ table: string; eqs: Row }>) {
	return {
		from(table: string) {
			const eqs: Row = {};
			const ins: Array<[string, unknown[]]> = [];
			const gtes: Array<[string, number]> = [];
			let order: [string, boolean] | null = null;
			let limit = Infinity;
			reads.push({ table, eqs });
			const matched = () => {
				const rows = (tables[table] ?? []).filter(
					(r) =>
						Object.entries(eqs).every(([c, v]) => r[c] === v) &&
						ins.every(([c, vs]) => vs.includes(r[c])) &&
						gtes.every(([c, v]) => (r[c] as number) >= v),
				);
				if (order) {
					const [c, asc] = order;
					rows.sort((a, b) => {
						const x = a[c] as string | number;
						const y = b[c] as string | number;
						return (x < y ? -1 : x > y ? 1 : 0) * (asc ? 1 : -1);
					});
				}
				return rows.slice(0, limit);
			};
			const q: Record<string, unknown> = {};
			q.select = () => q;
			q.eq = (c: string, v: unknown) => {
				eqs[c] = v;
				return q;
			};
			q.in = (c: string, vs: unknown[]) => {
				ins.push([c, vs]);
				return q;
			};
			q.gte = (c: string, v: number) => {
				gtes.push([c, v]);
				return q;
			};
			q.order = (c: string, opts?: { ascending?: boolean }) => {
				order = [c, opts?.ascending !== false];
				return q;
			};
			q.limit = (n: number) => {
				limit = n;
				return q;
			};
			q.maybeSingle = () => Promise.resolve({ data: matched()[0] ?? null, error: null });
			q.then = (onFulfilled: (v: unknown) => unknown, onRejected?: (e: unknown) => unknown) =>
				Promise.resolve({ data: matched(), error: null }).then(onFulfilled, onRejected);
			return q;
		},
	};
}

function plan(id: string, start: string, end: string, extra: Row = {}): Row {
	return { id, name: id, user_id: USER, status: 'active', is_template: false, start_date: start, end_date: end, ...extra };
}

/// `count` weeks of `planId`, each with one workout on its first day.
function weeksOf(planId: string, start: string, count: number): { weeks: Row[]; workouts: Row[] } {
	const startMs = Date.parse(start);
	const weeks: Row[] = [];
	const workouts: Row[] = [];
	for (let i = 0; i < count; i++) {
		const id = `${planId}-w${i}`;
		weeks.push({ id, plan_id: planId, week_index: i, phase: 'base' });
		workouts.push({
			id: `${id}-k`,
			week_id: id,
			kind: 'easy',
			scheduled_date: new Date(startMs + i * 7 * DAY_MS).toISOString().slice(0, 10),
			target_hr_min_bpm: 130,
			target_hr_max_bpm: 145,
		});
	}
	return { weeks, workouts };
}

// A marathon block, an ultra block queued straight after it, a summer block
// months later, and a finished spring block before them; plus rows the Coach
// must never read: a template, and another runner's plan over the same dates.
const SPRING = plan('spring', '2026-01-05', '2026-04-26', { status: 'completed' });
const MARATHON = plan('marathon', '2026-08-03', '2026-11-15');
const ULTRA = plan('ultra', '2026-11-16', '2027-03-28');
const SUMMER = plan('summer', '2027-06-07', '2027-08-29');
const TEMPLATE = plan('template', '2026-11-16', '2027-03-28', { is_template: true });
const OTHER = plan('other', '2026-11-16', '2027-03-28', { user_id: 'user-2' });

function fixture(plans: Row[] = [SPRING, MARATHON, ULTRA, SUMMER, TEMPLATE, OTHER]) {
	const parts = [
		weeksOf('spring', '2026-01-05', 16),
		weeksOf('marathon', '2026-08-03', 15),
		weeksOf('ultra', '2026-11-16', 19),
		weeksOf('summer', '2027-06-07', 12),
		weeksOf('template', '2026-11-16', 19),
		weeksOf('other', '2026-11-16', 19),
	];
	return {
		training_plans: plans,
		plan_weeks: parts.flatMap((p) => p.weeks),
		plan_workouts: parts.flatMap((p) => p.workouts),
	};
}

const PROFILE: CoachProfileRow = {
	display_name: 'Runner',
	preferred_unit: 'km',
	health_data_consent_at: '2026-06-01T00:00:00.000Z',
};

interface Block {
	plan: Row;
	plan_weeks: Row[];
	plan_workouts: Row[];
}

async function context(
	scope: CoachPlanScope,
	today: string,
	planId: string | null = null,
	tables = fixture(),
	profile = PROFILE,
) {
	const reads: Array<{ table: string; eqs: Row }> = [];
	const ctx = await buildContext(
		stubSupabase(tables, reads) as never,
		USER,
		planId,
		10,
		profile,
		today,
		AI_DISCLOSURE_CURRENT_VERSION,
		scope,
	);
	return { data: ctx.data as Record<string, unknown>, reads };
}

const weekIndexes = (b: Block) => b.plan_weeks.map((w) => w.week_index);
const planIds = (blocks: Block[]) => blocks.map((b) => b.plan.id);

test('coachPlanWeekWindow starts two weeks before the anchor week and spans the week cap', () => {
	// 2026-10-15 is in week 10 of a plan that started 2026-08-03.
	const { fromMs, toMs } = coachPlanWeekWindow('2026-08-03', '2026-10-15');
	assert.equal(new Date(fromMs).toISOString().slice(0, 10), '2026-09-28');
	assert.equal(toMs - fromMs, COACH_PLAN_WEEKS_CAP * 7 * DAY_MS);
	// Before the plan starts, the window opens on its first day.
	const early = coachPlanWeekWindow('2026-08-03', '2026-07-01');
	assert.equal(new Date(early.fromMs).toISOString().slice(0, 10), '2026-08-03');
});

test('a season is the current plan then the plans chained after it, in date order', async () => {
	const { data } = await context('season', '2026-10-15');
	assert.equal('plan' in data, false, 'a season is sent as blocks, not the flat plan keys');
	const season = data.season as Block[];
	assert.deepEqual(planIds(season), ['marathon', 'ultra']);
	// Weeks 8-14 of the marathon, then ultra weeks starting before 2027-02-15.
	assert.deepEqual(weekIndexes(season[0]), [8, 9, 10, 11, 12, 13, 14]);
	assert.deepEqual(weekIndexes(season[1]), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
	// Each workout travels with the plan its week belongs to.
	for (const block of season) {
		const weekIds = new Set(block.plan_weeks.map((w) => w.id));
		assert.equal(block.plan_workouts.length, block.plan_weeks.length);
		for (const w of block.plan_workouts) assert.ok(weekIds.has(w.week_id), `${w.week_id}`);
	}
});

test('the season is bounded by the week window, not by how many plans are queued', async () => {
	const { data, reads } = await context('season', '2026-10-15');
	const season = data.season as Block[];
	const total = season.reduce((n, b) => n + b.plan_weeks.length, 0);
	assert.equal(total, COACH_PLAN_WEEKS_CAP);
	// The summer block starts after the window closes: not sent, not read.
	assert.equal(planIds(season).includes('summer'), false);
	const weekReads = reads.filter((r) => r.table === 'plan_weeks').map((r) => r.eqs.plan_id);
	assert.equal(weekReads.includes('summer'), false);
});

test('a block queued after a gap sends only the weeks that start inside the window', async () => {
	// The window runs to 2027-02-15; an ultra starting 2027-01-25 has three
	// weeks inside it, though the week cap would have room for thirteen.
	const ultra = plan('ultra', '2027-01-25', '2027-06-06');
	const tables = fixture([MARATHON, ultra]);
	tables.plan_weeks = [
		...weeksOf('marathon', '2026-08-03', 15).weeks,
		...weeksOf('ultra', '2027-01-25', 19).weeks,
	];
	const { data } = await context('season', '2026-10-15', null, tables);
	const season = data.season as Block[];
	assert.deepEqual(weekIndexes(season[1]), [0, 1, 2]);
});

test('the week cap holds across plans when the date window would allow more', async () => {
	// The marathon stops mid-week and the ultra starts the next day, so the
	// window holds 21 plan weeks; the cap still sends 20.
	const marathon = { ...MARATHON, end_date: '2026-11-11' };
	const ultra = plan('ultra', '2026-11-12', '2027-03-28');
	const tables = fixture([marathon, ultra]);
	tables.plan_weeks = [
		...weeksOf('marathon', '2026-08-03', 15).weeks,
		...weeksOf('ultra', '2026-11-12', 19).weeks,
	];
	const { data } = await context('season', '2026-10-15', null, tables);
	const season = data.season as Block[];
	assert.deepEqual(weekIndexes(season[0]), [8, 9, 10, 11, 12, 13, 14]);
	assert.equal(season[1].plan_weeks.length, COACH_PLAN_WEEKS_CAP - 7);
});

test('before the first block starts, the season opens on it and still fills the window', async () => {
	const { data } = await context('season', '2026-07-01');
	const season = data.season as Block[];
	assert.deepEqual(planIds(season), ['marathon', 'ultra']);
	assert.equal(season[0].plan_weeks.length, 15);
	assert.deepEqual(weekIndexes(season[1]), [0, 1, 2, 3, 4]);
});

test('a season never reaches back to the block before the current one, a template or another runner', async () => {
	const { data } = await context('season', '2026-12-01');
	const ids = planIds(data.season as Block[]);
	assert.equal(ids[0], 'ultra');
	for (const id of ['marathon', 'spring', 'template', 'other']) {
		assert.equal(ids.includes(id), false, id);
	}
});

test('a season anchored on a pinned plan starts at it, even with none of its weeks in the window', async () => {
	const { data } = await context('season', '2026-10-15', 'spring');
	const season = data.season as Block[];
	assert.deepEqual(planIds(season), ['spring', 'marathon', 'ultra']);
	assert.deepEqual(season[0].plan_weeks, []);
	assert.deepEqual(weekIndexes(season[1]), [8, 9, 10, 11, 12, 13, 14]);
});

test('a pinned plan in plan scope is that plan alone; a fully elapsed one falls back to its final weeks', async () => {
	const { data } = await context('plan', '2026-10-15', 'spring');
	assert.equal((data.plan as Row).id, 'spring');
	assert.equal('season' in data, false);
	assert.equal((data.plan_weeks as Row[]).length, 16);
	assert.equal((data.plan_weeks as Row[])[0].week_index, 0);
});

test('plan scope without a pin is the current plan only, as before the season picker', async () => {
	const { data } = await context('plan', '2026-10-15');
	assert.equal((data.plan as Row).id, 'marathon');
	assert.deepEqual((data.plan_weeks as Row[]).map((w) => w.week_index), [8, 9, 10, 11, 12, 13, 14]);
});

test('"No plan" sends no plan and reads none', async () => {
	const { data, reads } = await context('none', '2026-10-15', null);
	assert.equal(data.plan, null);
	assert.deepEqual(data.plan_weeks, []);
	assert.deepEqual(data.plan_workouts, []);
	assert.equal(
		reads.some((r) => ['training_plans', 'plan_weeks', 'plan_workouts'].includes(r.table)),
		false,
	);
});

test('a season with no active plan is empty, and holds HR targets back without health consent', async () => {
	const none = await context('season', '2026-10-15', null, fixture([SPRING]));
	assert.deepEqual(none.data.season, []);

	const { data } = await context('season', '2026-10-15', null, fixture(), {
		...PROFILE,
		health_data_consent_at: null,
	});
	for (const block of data.season as Block[]) {
		for (const w of block.plan_workouts) {
			assert.equal(w.target_hr_min_bpm, null);
			assert.equal(w.target_hr_max_bpm, null);
		}
	}
});
