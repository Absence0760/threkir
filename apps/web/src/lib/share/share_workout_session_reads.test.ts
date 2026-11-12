// What the logged-out workout and session-plan share pages read, and what they
// hand back. The sibling suites pin the error and not-found paths; these pin
// the read path itself — which relation each query names, which filters it
// applies, which columns it asks for — and that the returned object carries
// only the documented fields. A share page is anonymous, so a read of a base
// table (owner-only since 20270313_001 for the gym tables) or a column outside
// the public set is exactly the leak the redacted views exist to prevent.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { SupabaseClient } from '@supabase/supabase-js';

import { lookupSharedWorkout } from './share_workout_lookup';
import { lookupSharedSession } from './share_session_lookup';

const ID = '11111111-2222-4333-8444-555555555555';
const OWNER = '99999999-8888-4777-8666-555555555555';
const config = { supabaseUrl: 'http://localhost', supabaseAnonKey: 'anon' };

interface Query {
	table: string;
	select: string;
	filters: Array<[string, string, unknown]>;
}

interface RpcCall {
	fn: string;
	args: unknown;
}

/// A chainable PostgREST stand-in that records every call. `rows` maps a
/// relation to what its query resolves with; `profile` is the RPC's row.
function recordingClient(
	rows: Record<string, unknown>,
	profile: unknown = null
): { client: SupabaseClient; queries: Query[]; rpcs: RpcCall[] } {
	const queries: Query[] = [];
	const rpcs: RpcCall[] = [];
	const client = {
		from(table: string) {
			const q: Query = { table, select: '', filters: [] };
			queries.push(q);
			const result = () => ({ data: rows[table] ?? null, error: null });
			const chain = {
				select(cols: string) {
					q.select = cols;
					return chain;
				},
				eq(col: string, v: unknown) {
					q.filters.push(['eq', col, v]);
					return chain;
				},
				order(col: string, opts: unknown) {
					q.filters.push(['order', col, opts]);
					return chain;
				},
				maybeSingle: async () => result(),
				then(resolve: (v: unknown) => unknown) {
					return Promise.resolve(result()).then(resolve);
				}
			};
			return chain;
		},
		rpc(fn: string, args: unknown) {
			rpcs.push({ fn, args });
			return { maybeSingle: async () => ({ data: profile, error: null }) };
		}
	} as unknown as SupabaseClient;
	return { client, queries, rpcs };
}

const cols = (q: Query) => q.select.split(',').map((c) => c.trim());

const WORKOUT_ROW = {
	id: ID,
	user_id: OWNER,
	title: 'Push day',
	started_at: '2026-08-01T06:00:00Z',
	set_count: 2,
	volume_kg: 1200,
	is_public: true
};

test('workout share reads only the redacted views, filtered to this public id', async () => {
	const { client, queries } = recordingClient({
		public_gym_workouts: WORKOUT_ROW,
		public_gym_sets: []
	});
	await lookupSharedWorkout(ID, config, () => client);
	assert.deepEqual(
		queries.map((q) => q.table),
		['public_gym_workouts', 'public_gym_sets']
	);
	assert.deepEqual(queries[0].filters, [
		['eq', 'id', ID],
		['eq', 'is_public', true]
	]);
	assert.deepEqual(queries[1].filters, [
		['eq', 'workout_id', ID],
		['order', 'set_index', { ascending: true }]
	]);
});

test('workout share asks for no notes, RPE or other private set columns', async () => {
	const { client, queries } = recordingClient({
		public_gym_workouts: WORKOUT_ROW,
		public_gym_sets: []
	});
	await lookupSharedWorkout(ID, config, () => client);
	assert.deepEqual(cols(queries[0]), [
		'id',
		'user_id',
		'title',
		'started_at',
		'set_count',
		'volume_kg',
		'is_public'
	]);
	assert.deepEqual(cols(queries[1]), ['set_index', 'exercise_name', 'reps', 'weight_kg', 'duration_s']);
	for (const q of queries) {
		assert.ok(!/\bnotes\b|\brpe\b|\*/.test(q.select), `${q.table} selects no private column`);
	}
});

test('workout share returns the documented fields only, and the owner name via the public RPC', async () => {
	const { client, rpcs } = recordingClient(
		{ public_gym_workouts: WORKOUT_ROW, public_gym_sets: [{ set_index: 0, exercise_name: 'Squat', reps: 5, weight_kg: 100, duration_s: null }] },
		{ display_name: 'Ana', date_of_birth: '1990-01-01', gender: 'female' }
	);
	const out = await lookupSharedWorkout(ID, config, () => client);
	assert.deepEqual(Object.keys(out.workout ?? {}).sort(), [
		'id',
		'set_count',
		'sets',
		'started_at',
		'title',
		'user_id',
		'volume_kg'
	]);
	assert.equal(out.displayName, 'Ana');
	assert.deepEqual(rpcs, [{ fn: 'public_profile_by_id', args: { p_id: OWNER } }]);
});

test('an ownerless workout makes no profile lookup and has no display name', async () => {
	const { client, rpcs } = recordingClient({
		public_gym_workouts: { ...WORKOUT_ROW, user_id: null },
		public_gym_sets: []
	});
	const out = await lookupSharedWorkout(ID, config, () => client);
	assert.equal(out.displayName, null);
	assert.equal(rpcs.length, 0);
	assert.deepEqual(out.workout?.sets, []);
});

const PLAN_ROW = {
	id: ID,
	author_id: OWNER,
	title: 'Hip mobility flow',
	discipline: 'yoga',
	equipment: 'mat',
	est_duration_min: 30,
	is_public: true
};

test('session share reads the plan filtered to this public id, and its children by plan id in order', async () => {
	const { client, queries } = recordingClient({
		session_plans: PLAN_ROW,
		session_plan_blocks: [],
		session_plan_items: []
	});
	await lookupSharedSession(ID, config, () => client);
	assert.deepEqual(
		queries.map((q) => q.table),
		['session_plans', 'session_plan_blocks', 'session_plan_items']
	);
	assert.deepEqual(queries[0].filters, [
		['eq', 'id', ID],
		['eq', 'is_public', true]
	]);
	for (const child of queries.slice(1)) {
		assert.deepEqual(child.filters, [
			['eq', 'plan_id', ID],
			['order', 'position', { ascending: true }]
		]);
	}
});

test('session share returns the documented plan fields only, with the author name via the public RPC', async () => {
	const { client, rpcs, queries } = recordingClient(
		{ session_plans: PLAN_ROW, session_plan_blocks: [], session_plan_items: [] },
		{ display_name: 'Dani', email: 'dani@example.com' }
	);
	const out = await lookupSharedSession(ID, config, () => client);
	assert.deepEqual(Object.keys(out.session ?? {}).sort(), [
		'author_id',
		'blocks',
		'discipline',
		'equipment',
		'est_duration_min',
		'id',
		'items',
		'title'
	]);
	assert.equal(out.displayName, 'Dani');
	assert.deepEqual(rpcs, [{ fn: 'public_profile_by_id', args: { p_id: OWNER } }]);
	assert.ok(queries.every((q) => !q.select.includes('*')), 'no wildcard select');
	assert.ok(!queries.some((q) => q.table === 'user_profiles'), 'the profile table is never read');
});

test('a missing config or a malformed id makes no request at all', async () => {
	for (const [id, cfg] of [
		[ID, null],
		[ID, { supabaseUrl: '', supabaseAnonKey: 'anon' }],
		['not-a-uuid', config],
		[`${ID}' or 1=1`, config]
	] as const) {
		let made = 0;
		const make = () => {
			made++;
			return recordingClient({}).client;
		};
		const w = await lookupSharedWorkout(id, cfg, make);
		const s = await lookupSharedSession(id, cfg, make);
		assert.deepEqual(w, { workout: null, displayName: null });
		assert.deepEqual(s, { session: null, displayName: null });
		assert.equal(made, 0, `no client for ${String(id)}`);
	}
});
