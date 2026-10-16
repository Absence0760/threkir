import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { PlanOverlapError } from '../core/supabase_error';
import type { PlanOverlapChoice } from '../core/data';
import { buildSeason, type SeasonPlanDraft } from './season_plan';
import { createSeasonPlans, type SeasonCreateDeps } from './season_create';
import type { OverlapPlan } from './plan_overlap';

function drafts(): SeasonPlanDraft[] {
	const r = buildSeason({
		races: [
			{ name: 'Richmond Marathon', date: '2026-11-14', distanceM: 42_195, priority: 'A', goalTimeSec: null },
			{ name: 'Comrades', date: '2027-06-13', distanceM: 87_000, priority: 'A', goalTimeSec: null },
			{ name: 'Big Sur', date: '2027-10-24', distanceM: 42_195, priority: 'A', goalTimeSec: null },
		],
		todayIso: '2026-08-14',
		daysPerWeek: 4,
	});
	assert.ok(r.ok);
	return r.plans;
}

const OLD: OverlapPlan = { id: 'old', name: 'Base block', start_date: '2026-08-01', end_date: '2026-09-30' };

function overlapError(): Error {
	return new PlanOverlapError();
}

function fake(opts: {
	failAt?: number;
	overlapFirst?: boolean;
	laterHits?: number;
}): SeasonCreateDeps & { calls: Array<[string, PlanOverlapChoice]> } {
	const calls: Array<[string, PlanOverlapChoice]> = [];
	return {
		calls,
		async create(draft, overlap) {
			calls.push([draft.name, overlap]);
			const index = calls.length - 1;
			if (opts.overlapFirst && draft.name === 'Richmond Marathon' && overlap === 'refuse') throw overlapError();
			if (opts.failAt !== undefined && index === opts.failAt) throw new Error('boom');
			return { id: `id-${draft.name}` };
		},
		async lookupOverlaps(start) {
			if (opts.overlapFirst && start === '2026-08-16') return [OLD];
			if (opts.laterHits !== undefined && start === drafts()[opts.laterHits].startDate) return [OLD];
			return [];
		},
	};
}

test('createSeasonPlans writes every plan in order, the later ones refusing any overlap', async () => {
	const deps = fake({});
	const r = await createSeasonPlans(drafts(), { from: 0, firstOverlap: 'refuse', created: [] }, deps);
	assert.equal(r.kind, 'done');
	assert.deepEqual(deps.calls, [
		['Richmond Marathon', 'refuse'],
		['Comrades', 'refuse'],
		['Big Sur', 'refuse'],
	]);
	assert.deepEqual(
		(r as { created: unknown[] }).created,
		[
			{ index: 0, id: 'id-Richmond Marathon' },
			{ index: 1, id: 'id-Comrades' },
			{ index: 2, id: 'id-Big Sur' },
		]
	);
});

test('createSeasonPlans asks about an overlap on the first plan, then passes the choice to it alone', async () => {
	const deps = fake({ overlapFirst: true });
	const first = await createSeasonPlans(drafts(), { from: 0, firstOverlap: 'refuse', created: [] }, deps);
	assert.deepEqual(first, { kind: 'overlap', overlapping: [OLD] });
	const second = await createSeasonPlans(drafts(), { from: 0, firstOverlap: 'trim', created: [] }, deps);
	assert.equal(second.kind, 'done');
	assert.deepEqual(deps.calls.slice(1), [
		['Richmond Marathon', 'trim'],
		['Comrades', 'refuse'],
		['Big Sur', 'refuse'],
	]);
});

test('createSeasonPlans blocks the season before writing when a later plan overlaps an active plan', async () => {
	const deps = fake({ laterHits: 2 });
	const r = await createSeasonPlans(drafts(), { from: 0, firstOverlap: 'refuse', created: [] }, deps);
	assert.deepEqual(r, { kind: 'blocked', index: 2, overlapping: [OLD] });
	assert.deepEqual(deps.calls, []);
});

test('createSeasonPlans reports a failure part-way with what was created, and resumes from it', async () => {
	const deps = fake({ failAt: 1 });
	const r = await createSeasonPlans(drafts(), { from: 0, firstOverlap: 'refuse', created: [] }, deps);
	assert.equal(r.kind, 'failed');
	const failed = r as Extract<typeof r, { kind: 'failed' }>;
	assert.equal(failed.failedIndex, 1);
	assert.deepEqual(failed.created, [{ index: 0, id: 'id-Richmond Marathon' }]);
	assert.equal((failed.error as Error).message, 'boom');

	const retry = fake({});
	const resumed = await createSeasonPlans(drafts(), { from: 1, firstOverlap: 'refuse', created: failed.created }, retry);
	assert.equal(resumed.kind, 'done');
	assert.deepEqual(retry.calls, [
		['Comrades', 'refuse'],
		['Big Sur', 'refuse'],
	]);
	assert.deepEqual(
		(resumed as { created: { index: number }[] }).created.map((c) => c.index),
		[0, 1, 2]
	);
});
