/// club-verification-recheck's handler driven with a fake service client and a
/// fake resolver: the cron gate, the due list, a pass, a miss, an inconclusive
/// result that is skipped, and a lapse. The schedule and its Vault guard are
/// pinned from the migration source.
///
/// Run with `cd apps/backend && deno test --allow-read --allow-env
/// supabase/functions/club-verification-recheck/handler.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { CRON_SECRET_MIN_CHARS } from '../events-refund-sweep/lib.ts';
import { DOH_URL, proofRecord } from '../_shared/domain_proof.ts';
import { makeRecheckHandler, RECHECKS_PER_RUN } from './handler.ts';

const SECRET = 's'.repeat(CRON_SECRET_MIN_CHARS);
const SQL = Deno.readTextFileSync(
	new URL('../../migrations/20271120000004_club_verification_requests.sql', import.meta.url),
);
const CONFIG = Deno.readTextFileSync(new URL('../../config.toml', import.meta.url));

interface Due {
	id: string;
	domain: string;
	token: string;
}

function harness(opts: {
	due?: Due[];
	txt?: Record<string, string[]>;
	resolverDown?: boolean;
	lapseOn?: string;
	env?: Record<string, string | undefined>;
} = {}) {
	const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
	const client = {
		rpc(name: string, args: Record<string, unknown>) {
			calls.push({ name, args });
			if (name === 'club_verifications_due_for_recheck') return Promise.resolve({ data: opts.due ?? [], error: null });
			if (name === 'record_club_verification_check') {
				const status = args.p_ok ? 'verified' : args.p_request_id === opts.lapseOn ? 'lapsed' : 'not_found';
				return Promise.resolve({ data: status, error: null });
			}
			return Promise.resolve({ data: [{ allowed: true, retry_after_seconds: 0 }], error: null });
		},
	} as unknown as DbClient;
	const env: Record<string, string | undefined> = { CRON_SECRET: SECRET, ...(opts.env ?? {}) };
	const handler = makeRecheckHandler({
		getEnv: (n) => env[n],
		serviceClient: () => client,
		proof: {
			fetch: (input: string) => {
				if (!input.startsWith(DOH_URL)) return Promise.reject(new TypeError('no host'));
				if (opts.resolverDown) return Promise.resolve(new Response('down', { status: 502 }));
				const u = new URL(input);
				const name = u.searchParams.get('name')!;
				const answers = u.searchParams.get('type') === 'TXT'
					? (opts.txt?.[name] ?? []).map((data) => ({ type: 16, data: `"${data}"` }))
					: [];
				return Promise.resolve(Response.json({ Status: 0, Answer: answers }));
			},
			timeoutMs: 1_000,
		},
	});
	return { handler, calls };
}

const cron = (bearer = SECRET) =>
	new Request('http://x/', { method: 'POST', headers: { Authorization: `Bearer ${bearer}` } });

Deno.test('an unset cron secret is 503 and does no work', async () => {
	const { handler, calls } = harness({ env: { CRON_SECRET: undefined } });
	assertEquals((await handler(cron())).status, 503);
	assertEquals(calls.length, 0);
});

Deno.test('a wrong bearer is 403 and reads no due list', async () => {
	const { handler, calls } = harness();
	assertEquals((await handler(cron('x'.repeat(CRON_SECRET_MIN_CHARS)))).status, 403);
	assert(!calls.some((c) => c.name === 'club_verifications_due_for_recheck'));
});

Deno.test('a missing bearer is 403', async () => {
	const { handler } = harness();
	assertEquals((await handler(new Request('http://x/', { method: 'POST' }))).status, 403);
});

Deno.test('the run asks for at most ten due approvals', async () => {
	const { handler, calls } = harness();
	assertEquals((await handler(cron())).status, 200);
	assertEquals(calls[0], { name: 'club_verifications_due_for_recheck', args: { p_limit: RECHECKS_PER_RUN } });
	assertEquals(RECHECKS_PER_RUN, 10);
});

Deno.test('a pass, a miss and a lapse are each recorded', async () => {
	const token = '1'.repeat(32);
	const { handler, calls } = harness({
		due: [
			{ id: 'a', domain: 'pass.example.org', token },
			{ id: 'b', domain: 'miss.example.org', token },
			{ id: 'c', domain: 'gone.example.org', token },
		],
		txt: { '_threkir-verification.pass.example.org': [proofRecord(token)] },
		lapseOn: 'c',
	});
	const body = await (await handler(cron())).json();
	assertEquals(body, { checked: 3, verified: 1, failed: 1, lapsed: 1, skipped: 0, errors: 0 });
	const recorded = calls.filter((c) => c.name === 'record_club_verification_check');
	assertEquals(recorded.map((c) => [c.args.p_request_id, c.args.p_ok]), [['a', true], ['b', false], ['c', false]]);
});

Deno.test('an outage on our side is skipped, never counted against the club', async () => {
	const { handler, calls } = harness({
		due: [{ id: 'a', domain: 'pass.example.org', token: '1'.repeat(32) }],
		resolverDown: true,
	});
	const body = await (await handler(cron())).json();
	assertEquals(body.skipped, 1);
	assert(!calls.some((c) => c.name === 'record_club_verification_check'));
});

Deno.test('the schedule is hourly and fails closed without its Vault secrets', () => {
	assert(/cron\.schedule\(\s*'club-verification-recheck',\s*'17 \* \* \* \*'/.test(SQL));
	assert(/name = 'club_verification_recheck_url'/.test(SQL));
	assert(/name = 'cron_secret'/.test(SQL));
	assert(/if v_url is null or v_secret is null then\s+return null;/.test(SQL));
});

Deno.test('the cron entry point is reachable without a user JWT', () => {
	assert(/\[functions\.club-verification-recheck\]\s+verify_jwt = false/.test(CONFIG));
	assert(!/\[functions\.club-verification\]\s+verify_jwt = false/.test(CONFIG), 'the user-facing check keeps the JWT gate');
});
