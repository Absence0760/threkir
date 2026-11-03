import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { SupabaseClient } from '@supabase/supabase-js';

import { lookupSharedPlan, parseSharedPlan } from './share_plan_lookup';

const PLAN_ID = '11111111-2222-4333-8444-555555555555';
const config = { supabaseUrl: 'http://localhost', supabaseAnonKey: 'anon' };

interface RpcCall {
	fn: string;
	args: unknown;
	opts: unknown;
}

function fakeClient(result: { data?: unknown; error?: unknown }, calls: RpcCall[] = []): SupabaseClient {
	return {
		from() {
			throw new Error('the share plan page must not read a table');
		},
		async rpc(fn: string, args: unknown, opts: unknown) {
			calls.push({ fn, args, opts });
			return { data: result.data ?? null, error: result.error ?? null };
		},
	} as unknown as SupabaseClient;
}

async function captureErrors(fn: () => Promise<unknown>): Promise<string[]> {
	const lines: string[] = [];
	const original = console.error;
	console.error = (...args: unknown[]) => {
		lines.push(args.map((a) => String(a)).join(' '));
	};
	try {
		await fn();
	} finally {
		console.error = original;
	}
	return lines;
}

const DOC = {
	id: PLAN_ID,
	name: 'Spring marathon block',
	goal_event: 'distance_full',
	goal_distance_m: 42195,
	days_per_week: 5,
	author: { name: 'Creator Cat', handle: 'creatorcat' },
	weeks: [
		{
			week_index: 1,
			phase: 'build',
			target_volume_m: 45000,
			workouts: [{ day: 9, kind: 'tempo', target_distance_m: 10000, pace_zone: 'threshold' }],
		},
		{ week_index: 0, phase: 'base', target_volume_m: 40000, workouts: [] },
	],
};

test('reads the redacted RPC as a GET, never a table', async () => {
	const calls: RpcCall[] = [];
	const { plan } = await lookupSharedPlan(PLAN_ID, config, () => fakeClient({ data: DOC }, calls));
	assert.deepEqual(calls, [{ fn: 'public_plan_share', args: { p_id: PLAN_ID }, opts: { get: true } }]);
	assert.equal(plan?.name, 'Spring marathon block');
	assert.deepEqual(
		plan?.weeks.map((w) => w.week_index),
		[0, 1],
		'weeks come back in order',
	);
	assert.equal(plan?.weeks[1].workouts[0].day, 9);
});

test('a null document (not public, or the gate closed) is a silent not-found', async () => {
	let result: Awaited<ReturnType<typeof lookupSharedPlan>> | undefined;
	const lines = await captureErrors(async () => {
		result = await lookupSharedPlan(PLAN_ID, config, () => fakeClient({ data: null }));
	});
	assert.equal(result?.plan, null);
	assert.deepEqual(lines, []);
});

test('an RPC error surfaces the tagged upstream line', async () => {
	let result: Awaited<ReturnType<typeof lookupSharedPlan>> | undefined;
	const lines = await captureErrors(async () => {
		result = await lookupSharedPlan(PLAN_ID, config, () =>
			fakeClient({ error: { message: 'upstream connect error' } }),
		);
	});
	assert.equal(result?.plan, null);
	assert.deepEqual(lines, ['[share-plan] upstream_unreachable']);
});

test('a thrown fetch surfaces the tagged line', async () => {
	const lines = await captureErrors(() =>
		lookupSharedPlan(PLAN_ID, config, () => {
			throw new Error('fetch failed');
		}),
	);
	assert.equal(lines.length, 1);
	assert.match(lines[0], /^\[share-plan\] upstream_unreachable/);
});

test('a non-uuid id or missing config never queries', async () => {
	const boom = () => {
		throw new Error('should not have queried');
	};
	const lines = await captureErrors(async () => {
		assert.equal((await lookupSharedPlan('hello', config, boom)).plan, null);
		assert.equal((await lookupSharedPlan(PLAN_ID, null, boom)).plan, null);
	});
	assert.deepEqual(lines, []);
});

test('parseSharedPlan keeps only the documented keys', () => {
	const plan = parseSharedPlan({
		...DOC,
		vdot: 55,
		user_id: 'x',
		weeks: [
			{
				week_index: 0,
				phase: 'base',
				target_volume_m: 1,
				notes: 'secret',
				workouts: [{ day: 0, kind: 'easy', target_pace_sec_per_km: 300, notes: 'secret' }],
			},
		],
	});
	const text = JSON.stringify(plan);
	for (const leaked of ['vdot', 'user_id', 'notes', 'target_pace', 'secret']) {
		assert.ok(!text.includes(leaked), `${leaked} must not survive the parse`);
	}
	assert.equal(plan?.weeks[0].workouts[0].kind, 'easy');
});

test('parseSharedPlan rejects a document missing its required fields', () => {
	assert.equal(parseSharedPlan(null), null);
	assert.equal(parseSharedPlan([]), null);
	assert.equal(parseSharedPlan({ ...DOC, id: undefined }), null);
	assert.equal(parseSharedPlan({ ...DOC, goal_distance_m: 'x' }), null);
	assert.equal(parseSharedPlan({ ...DOC, author: null })?.author, null);
});
