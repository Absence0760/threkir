import { afterEach, test } from 'node:test';
import assert from 'node:assert/strict';

import { lookupSharedRun } from './share_run_lookup';
import { lookupSharedProfile } from './share_profile_lookup';
import { lookupSharedRecap } from './share_recap_lookup';

// These lookups run anonymously behind the public /share/* Lambdas, so what
// they are allowed to ask PostgREST for is the privacy boundary, and the
// `upstream_unreachable` log line is what a CloudWatch alarm pages on.

const CONFIG = { supabaseUrl: 'https://stub.supabase.co', supabaseAnonKey: 'anon' };
const RUN_ID = '11111111-1111-4111-8111-111111111111';
const USER_ID = '22222222-2222-4222-8222-222222222222';

const realFetch = globalThis.fetch;
const realError = console.error;
let requests: URL[] = [];
let errors: string[] = [];

/** Answer each PostgREST path with the body registered for it; record every URL. */
function stubPostgrest(routes: Record<string, { status?: number; body: unknown }>) {
	requests = [];
	errors = [];
	console.error = (...args: unknown[]) => {
		errors.push(args.map(String).join(' '));
	};
	globalThis.fetch = (async (input: RequestInfo | URL) => {
		const url = new URL(input instanceof Request ? input.url : String(input));
		requests.push(url);
		const hit = Object.entries(routes).find(([path]) => url.pathname.endsWith(path));
		if (!hit) return new Response('[]', { status: 200 });
		const [, { status = 200, body }] = hit;
		return new Response(JSON.stringify(body), {
			status,
			headers: { 'content-type': 'application/json' },
		});
	}) as typeof fetch;
}

afterEach(() => {
	globalThis.fetch = realFetch;
	console.error = realError;
});

const paths = () => requests.map((u) => u.pathname);
const alarmed = () => errors.some((e) => e.includes('upstream_unreachable'));

test('run: a malformed id is a quiet not-found that never reaches PostgREST', async () => {
	stubPostgrest({});
	const r = await lookupSharedRun('hello', CONFIG);
	assert.deepEqual(r, { run: null, displayName: null });
	assert.equal(requests.length, 0);
	assert.equal(alarmed(), false);
});

test('run: missing config makes no request at all', async () => {
	stubPostgrest({});
	assert.deepEqual(await lookupSharedRun(RUN_ID, null), { run: null, displayName: null });
	assert.deepEqual(
		await lookupSharedRun(RUN_ID, { supabaseUrl: CONFIG.supabaseUrl, supabaseAnonKey: '' }),
		{ run: null, displayName: null },
	);
	assert.equal(requests.length, 0);
});

test('run: reads the public_runs view and the profile RPC, never the base tables', async () => {
	stubPostgrest({
		'/rest/v1/public_runs': { body: [{ id: RUN_ID, user_id: USER_ID, distance_m: 5000 }] },
		'/rest/v1/rpc/public_profile_by_id': { body: [{ display_name: 'Ana' }] },
	});
	const r = await lookupSharedRun(RUN_ID, CONFIG);
	assert.equal(r.run?.id, RUN_ID);
	assert.equal(r.displayName, 'Ana');
	assert.deepEqual(paths(), ['/rest/v1/public_runs', '/rest/v1/rpc/public_profile_by_id']);
	assert.equal(requests[0].searchParams.get('id'), `eq.${RUN_ID}`);
	assert.equal(requests[1].searchParams.get('p_id'), USER_ID);
	for (const p of paths()) {
		assert.ok(!/\/rest\/v1\/(runs|user_profiles|public_profiles)$/.test(p), p);
	}
});

test('run: an ownerless run skips the profile lookup and has no display name', async () => {
	stubPostgrest({ '/rest/v1/public_runs': { body: [{ id: RUN_ID, user_id: null }] } });
	const r = await lookupSharedRun(RUN_ID, CONFIG);
	assert.equal(r.run?.id, RUN_ID);
	assert.equal(r.displayName, null);
	assert.deepEqual(paths(), ['/rest/v1/public_runs']);
});

test('run: a PostgREST error is logged with the alarm tag; a clean miss is not', async () => {
	stubPostgrest({
		'/rest/v1/public_runs': { status: 400, body: { code: 'PGRST100', message: 'bad request' } },
	});
	assert.deepEqual(await lookupSharedRun(RUN_ID, CONFIG), { run: null, displayName: null });
	assert.equal(alarmed(), true);

	stubPostgrest({ '/rest/v1/public_runs': { body: [] } });
	assert.deepEqual(await lookupSharedRun(RUN_ID, CONFIG), { run: null, displayName: null });
	assert.equal(alarmed(), false);
});

test('run: a thrown network failure degrades to not-found with the alarm tag', async () => {
	stubPostgrest({});
	globalThis.fetch = (async () => {
		throw new TypeError('fetch failed');
	}) as typeof fetch;
	assert.deepEqual(await lookupSharedRun(RUN_ID, CONFIG), { run: null, displayName: null });
	assert.equal(alarmed(), true);
});

test('profile: a malformed id never reaches the uuid RPC, so it cannot page anyone', async () => {
	stubPostgrest({
		'/rest/v1/rpc/public_profile_by_id': {
			status: 400,
			body: { code: '22P02', message: 'invalid input syntax for type uuid' },
		},
	});
	assert.deepEqual(await lookupSharedProfile('not-a-uuid', CONFIG), { profile: null });
	assert.equal(requests.length, 0);
	assert.equal(alarmed(), false);
});

test('profile: only id, display name and avatar leave the RPC row', async () => {
	stubPostgrest({
		'/rest/v1/rpc/public_profile_by_id': {
			body: [{ display_name: 'Ana', date_of_birth: '1990-01-01', gender: 'f' }],
		},
	});
	const { profile } = await lookupSharedProfile(USER_ID, CONFIG);
	assert.deepEqual(profile, { id: USER_ID, display_name: 'Ana', avatar_url: null });
});

test('recap: a malformed id never reaches the uuid RPC', async () => {
	stubPostgrest({
		'/rest/v1/rpc/public_recap_by_id': {
			status: 400,
			body: { code: '22P02', message: 'invalid input syntax for type uuid' },
		},
	});
	assert.deepEqual(await lookupSharedRecap('2026', CONFIG), { recap: null });
	assert.equal(requests.length, 0);
	assert.equal(alarmed(), false);
});

test('recap: a missing snapshot becomes an empty object and the owner name comes from the RPC', async () => {
	stubPostgrest({
		'/rest/v1/rpc/public_recap_by_id': {
			body: [{ id: RUN_ID, user_id: USER_ID, period_kind: 'year', period_key: '2026', snapshot: null }],
		},
		'/rest/v1/rpc/public_profile_by_id': { body: [{ display_name: 'Ana' }] },
	});
	const { recap } = await lookupSharedRecap(RUN_ID, CONFIG);
	assert.deepEqual(recap, {
		id: RUN_ID,
		periodKind: 'year',
		periodKey: '2026',
		snapshot: {},
		displayName: 'Ana',
	});
	assert.deepEqual(paths(), ['/rest/v1/rpc/public_recap_by_id', '/rest/v1/rpc/public_profile_by_id']);
});
