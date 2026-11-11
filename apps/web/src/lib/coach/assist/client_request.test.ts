// What the coach assistant panel receives for every answer of
// /api/coach/assist (issue #1215 Phase 4), with fetch and the session stood
// in through postCoachAssistDraft's transport.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { AI_DISCLOSURE_ERROR } from '../../core/ai_disclosure';
import { payloadSha256Hex } from '../../util/payload_hash';
import { CoachAssistError, type CoachAssistErrorKind } from './client_kind';
import { postCoachAssistDraft, type CoachAssistTransport } from './client_request';
import { ATHLETE_CONSENT_REQUIRED } from './handler_codes';

const INPUT = {
	athleteId: '11111111-2222-4333-8444-555555555555',
	mode: 'reply' as const,
	request: '  keep it short  ',
	today: '2026-11-10',
	locale: 'en',
};

type Answer = Response | Error;

function json(status: number, body: unknown): Response {
	return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

function transport(answers: Answer[], tokens: { access?: string; refreshed?: string | Error } = {}) {
	const calls: { url: string; init: RequestInit }[] = [];
	let refreshes = 0;
	const io: CoachAssistTransport = {
		fetch: async (url, init) => {
			calls.push({ url, init });
			const next = answers.shift();
			if (!next) throw new Error('no answer queued');
			if (next instanceof Error) throw next;
			return next;
		},
		accessToken: async () => ('access' in tokens ? tokens.access : 'token-1'),
		refreshedToken: async () => {
			refreshes++;
			if (tokens.refreshed instanceof Error) throw tokens.refreshed;
			return tokens.refreshed;
		},
	};
	return { io, calls, refreshes: () => refreshes };
}

async function kindOf(promise: Promise<string>): Promise<CoachAssistErrorKind> {
	try {
		await promise;
	} catch (e) {
		assert.ok(e instanceof CoachAssistError, `expected a CoachAssistError, got ${e}`);
		return e.kind;
	}
	assert.fail('expected a refusal');
}

const header = (init: RequestInit, name: string) => (init.headers as Record<string, string>)[name];

test('a draft comes back, from a body that carries only the id, mode, request, date and locale', async () => {
	const t = transport([json(200, { draft: 'Nice work on Tuesday.' })]);
	assert.equal(await postCoachAssistDraft(INPUT, t.io), 'Nice work on Tuesday.');
	assert.equal(t.calls.length, 1);
	const { url, init } = t.calls[0];
	assert.equal(url, '/api/coach/assist');
	assert.equal(init.method, 'POST');
	assert.deepEqual(JSON.parse(init.body as string), {
		athlete_id: INPUT.athleteId,
		mode: 'reply',
		request: 'keep it short',
		today: '2026-11-10',
		locale: 'en',
	});
	assert.equal(header(init, 'X-Supabase-Authorization'), 'Bearer token-1');
	assert.equal(header(init, 'x-amz-content-sha256'), await payloadSha256Hex(init.body as string));
});

test('a blank request is left out of the body', async () => {
	const t = transport([json(200, { draft: 'ok' })]);
	await postCoachAssistDraft({ ...INPUT, request: '   ' }, t.io);
	assert.equal('request' in JSON.parse(t.calls[0].init.body as string), false);
});

test('no session is not_authenticated, and nothing is sent', async () => {
	const t = transport([], { access: undefined });
	assert.equal(await kindOf(postCoachAssistDraft(INPUT, t.io)), 'not_authenticated');
	assert.equal(t.calls.length, 0);
});

test('a 401 refreshes the session once and retries with the new token', async () => {
	const t = transport([json(401, {}), json(200, { draft: 'after refresh' })], { refreshed: 'token-2' });
	assert.equal(await postCoachAssistDraft(INPUT, t.io), 'after refresh');
	assert.equal(t.refreshes(), 1);
	assert.deepEqual(
		t.calls.map((c) => header(c.init, 'X-Supabase-Authorization')),
		['Bearer token-1', 'Bearer token-2'],
	);
});

test('a 401 after the retry is not_authenticated, and a failed refresh retries with the old token', async () => {
	const t = transport([json(401, {}), json(401, {})], { refreshed: new Error('refresh failed') });
	assert.equal(await kindOf(postCoachAssistDraft(INPUT, t.io)), 'not_authenticated');
	assert.equal(t.calls.length, 2);
	assert.equal(header(t.calls[1].init, 'X-Supabase-Authorization'), 'Bearer token-1');
});

test('each 4xx reaches the panel as the state it shows', async () => {
	const cases: [Response, CoachAssistErrorKind][] = [
		[json(403, { code: AI_DISCLOSURE_ERROR }), 'coach_consent'],
		[json(403, { code: ATHLETE_CONSENT_REQUIRED }), 'athlete_consent'],
		[json(403, { upgrade: true }), 'upgrade'],
		[json(403, { error: 'forbidden' }), 'not_your_athlete'],
		[json(429, { error: 'rate limited' }), 'rate_limited'],
		[json(400, { error: 'bad input' }), 'unavailable'],
		[json(404, { error: 'not found' }), 'unavailable'],
		[json(413, { error: 'too large' }), 'unavailable'],
	];
	for (const [res, kind] of cases) {
		const t = transport([res]);
		assert.equal(await kindOf(postCoachAssistDraft(INPUT, t.io)), kind, `${res.status} → ${kind}`);
		assert.equal(t.refreshes(), 0);
	}
});

test('the athlete-consent refusal is told apart from every other 403', async () => {
	const t = transport([json(403, { code: ATHLETE_CONSENT_REQUIRED, upgrade: true })]);
	assert.equal(await kindOf(postCoachAssistDraft(INPUT, t.io)), 'athlete_consent');
});

test('a 5xx, with a JSON body or none, is unavailable', async () => {
	for (const res of [json(503, { error: 'off' }), new Response('<html>Bad Gateway</html>', { status: 502 }), new Response(null, { status: 500 })]) {
		const t = transport([res]);
		assert.equal(await kindOf(postCoachAssistDraft(INPUT, t.io)), 'unavailable', String(res.status));
	}
});

test('a network failure is unavailable, not a raw TypeError', async () => {
	const t = transport([new TypeError('Failed to fetch')]);
	assert.equal(await kindOf(postCoachAssistDraft(INPUT, t.io)), 'unavailable');
});

test('a 200 with no draft, a blank one, a non-string one or a body that is not JSON is unavailable', async () => {
	for (const res of [
		json(200, {}),
		json(200, { draft: '   ' }),
		json(200, { draft: 42 }),
		new Response('not json', { status: 200 }),
	]) {
		const t = transport([res]);
		assert.equal(await kindOf(postCoachAssistDraft(INPUT, t.io)), 'unavailable');
	}
});
