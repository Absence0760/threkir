/// club-verification's handler driven with fakes: the method, auth, body and
/// rate-limit gates, a request the caller cannot see, a request that is no
/// longer pending, a passing and a failing check, and what is recorded. The
/// proof checks themselves are pinned in _shared/domain_proof.test.ts.
///
/// Run with `cd apps/backend && deno test --allow-read --allow-env
/// supabase/functions/club-verification/handler.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { DOH_URL, proofRecord } from '../_shared/domain_proof.ts';
import { type CheckableRequest, makeClubVerificationHandler } from './handler.ts';

const REQ_ID = '7f000000-0000-4000-8000-000000000001';
const TOKEN = 'abcdef0123456789abcdef0123456789';

function harness(opts: {
	user?: string | null;
	request?: CheckableRequest | null;
	txt?: string[];
	limited?: boolean;
	recordFails?: boolean;
} = {}) {
	const recorded: Array<{ id: string; ok: boolean; method: string | null }> = [];
	const handler = makeClubVerificationHandler({
		authenticate: () => Promise.resolve(opts.user === undefined ? 'user-1' : opts.user),
		rateLimit: () => Promise.resolve(opts.limited ? new Response('slow down', { status: 429 }) : null),
		loadRequest: () =>
			Promise.resolve(
				opts.request === undefined ? { id: REQ_ID, domain: 'race.example.org', token: TOKEN, status: 'pending' } : opts.request,
			),
		record: (id, result) => {
			recorded.push({ id, ok: result.verified, method: result.method });
			return Promise.resolve(opts.recordFails ? null : result.verified ? 'verified' : 'not_found');
		},
		proof: {
			fetch: (input: string) => {
				if (!input.startsWith(DOH_URL)) return Promise.reject(new TypeError('no host'));
				const u = new URL(input);
				const answers = u.searchParams.get('type') === 'TXT' &&
						u.searchParams.get('name') === '_threkir-verification.race.example.org'
					? (opts.txt ?? []).map((data) => ({ type: 16, data: `"${data}"` }))
					: [];
				return Promise.resolve(Response.json({ Status: 0, Answer: answers }));
			},
			timeoutMs: 1_000,
		},
	});
	return { handler, recorded };
}

const post = (body: unknown) =>
	new Request('http://x/club-verification', { method: 'POST', body: JSON.stringify(body) });

Deno.test('only POST is accepted', async () => {
	const { handler } = harness();
	assertEquals((await handler(new Request('http://x/', { method: 'GET' }))).status, 405);
});

Deno.test('a caller with no session is refused', async () => {
	const { handler, recorded } = harness({ user: null });
	assertEquals((await handler(post({ request_id: REQ_ID }))).status, 401);
	assertEquals(recorded.length, 0);
});

Deno.test('a malformed request id is refused', async () => {
	const { handler } = harness();
	assertEquals((await handler(post({ request_id: 'nope' }))).status, 400);
});

Deno.test('an over-budget caller is refused before any lookup', async () => {
	const { handler, recorded } = harness({ limited: true, txt: [proofRecord(TOKEN)] });
	assertEquals((await handler(post({ request_id: REQ_ID }))).status, 429);
	assertEquals(recorded.length, 0);
});

Deno.test('a request the caller cannot see is a 404', async () => {
	const { handler, recorded } = harness({ request: null });
	assertEquals((await handler(post({ request_id: REQ_ID }))).status, 404);
	assertEquals(recorded.length, 0);
});

Deno.test('a request that is no longer pending is not re-checked here', async () => {
	const { handler, recorded } = harness({
		request: { id: REQ_ID, domain: 'race.example.org', token: TOKEN, status: 'approved' },
	});
	assertEquals((await handler(post({ request_id: REQ_ID }))).status, 409);
	assertEquals(recorded.length, 0);
});

Deno.test('a passing DNS record is recorded as verified', async () => {
	const { handler, recorded } = harness({ txt: [proofRecord(TOKEN)] });
	const res = await handler(post({ request_id: REQ_ID }));
	assertEquals(res.status, 200);
	const body = await res.json();
	assertEquals(body.status, 'verified');
	assertEquals(body.method, 'dns_txt');
	assertEquals(recorded, [{ id: REQ_ID, ok: true, method: 'dns_txt' }]);
});

Deno.test('a missing proof is recorded as a miss with both outcomes', async () => {
	const { handler, recorded } = harness({ txt: [] });
	const res = await handler(post({ request_id: REQ_ID }));
	const body = await res.json();
	assertEquals(body.status, 'not_found');
	assertEquals(body.checks.dns_txt, 'not_found');
	assert(['unreachable', 'not_found'].includes(body.checks.well_known));
	assertEquals(recorded[0].ok, false);
});

Deno.test('a failed write is a 500, not a silent pass', async () => {
	const { handler } = harness({ txt: [proofRecord(TOKEN)], recordFails: true });
	assertEquals((await handler(post({ request_id: REQ_ID }))).status, 500);
});
