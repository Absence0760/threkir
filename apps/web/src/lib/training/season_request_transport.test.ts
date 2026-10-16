// Unit tests for the season request's client transport. Run via
// `npx tsx --test apps/web/src/lib/training/season_request_transport.test.ts`.
//
// The session and fetch are injected, so the body shape, the payload hash,
// the single 401 refresh-and-replay, the status-to-kind mapping and the
// strict parse of the 200 body all run without a browser client.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

import { PlanRequestError } from './plan_request_error';
import { SEASON_REQUEST_ASSUMPTIONS } from './season_request/races';
import {
	SEASON_REQUEST_PATH,
	parseSeasonRequestResult,
	sendSeasonRequest,
	type SeasonRequestDeps,
} from './season_request_transport';
import { seasonAssumptionMessageKey } from './season_request_labels';
import { en } from '../i18n/locales/en';

const RACE = { name: 'Comrades', date: '2027-06-13', distanceM: 89_000, priority: 'A', goalTimeSec: null };
const OK_BODY = { races: [RACE], assumptions: ['priority_a_assigned'] };

function response(status: number, body: unknown): Response {
	return new Response(typeof body === 'string' ? body : JSON.stringify(body), {
		status,
		headers: { 'content-type': 'application/json' },
	});
}

function deps(replies: Array<Response | Error>, opts: { token?: string | null; refreshed?: string | null; refreshThrows?: boolean } = {}) {
	const calls: Array<{ url: string; init: RequestInit }> = [];
	let refreshes = 0;
	const d: SeasonRequestDeps = {
		fetch: async (url, init) => {
			calls.push({ url, init });
			const next = replies.shift();
			if (!next) throw new Error('no reply queued');
			if (next instanceof Error) throw next;
			return next;
		},
		currentToken: async () => (opts.token === undefined ? 'tok-1' : opts.token),
		refreshToken: async () => {
			refreshes++;
			if (opts.refreshThrows) throw new Error('refresh failed');
			return opts.refreshed === undefined ? 'tok-2' : opts.refreshed;
		},
	};
	return { d, calls, refreshes: () => refreshes };
}

async function kindOf(p: Promise<unknown>): Promise<string> {
	try {
		await p;
	} catch (e) {
		assert.ok(e instanceof PlanRequestError, String(e));
		return e.kind;
	}
	throw new Error('expected a PlanRequestError');
}

test('posts the request and today with the bearer and the exact payload hash', async () => {
	const { d, calls } = deps([response(200, OK_BODY)]);
	const result = await sendSeasonRequest('Comrades in June', '2026-10-16', d);
	assert.deepEqual(result, OK_BODY);
	assert.equal(calls.length, 1);
	assert.equal(calls[0].url, SEASON_REQUEST_PATH);
	assert.equal(SEASON_REQUEST_PATH, '/api/coach/season-request');
	const body = calls[0].init.body as string;
	assert.deepEqual(JSON.parse(body), { request: 'Comrades in June', today: '2026-10-16' });
	const headers = calls[0].init.headers as Record<string, string>;
	assert.equal(headers['X-Supabase-Authorization'], 'Bearer tok-1');
	assert.equal(headers['x-amz-content-sha256'], createHash('sha256').update(body).digest('hex'));
	assert.equal(calls[0].init.method, 'POST');
});

test('no session is not_authenticated, and nothing is posted', async () => {
	for (const token of [null, '']) {
		const { d, calls } = deps([], { token });
		assert.equal(await kindOf(sendSeasonRequest('x', '2026-10-16', d)), 'not_authenticated');
		assert.equal(calls.length, 0);
	}
});

test('a 401 refreshes once and replays with the new token', async () => {
	const { d, calls, refreshes } = deps([response(401, {}), response(200, OK_BODY)]);
	const result = await sendSeasonRequest('x', '2026-10-16', d);
	assert.deepEqual(result, OK_BODY);
	assert.equal(refreshes(), 1);
	assert.equal(calls.length, 2);
	assert.equal((calls[1].init.headers as Record<string, string>)['X-Supabase-Authorization'], 'Bearer tok-2');
});

test('a second 401 is not retried again', async () => {
	const { d, calls } = deps([response(401, {}), response(401, {})]);
	assert.equal(await kindOf(sendSeasonRequest('x', '2026-10-16', d)), 'not_authenticated');
	assert.equal(calls.length, 2);
});

test('a refresh that fails or yields nothing keeps the original 401', async () => {
	for (const opts of [{ refreshThrows: true }, { refreshed: null }]) {
		const { d, calls } = deps([response(401, {})], opts);
		assert.equal(await kindOf(sendSeasonRequest('x', '2026-10-16', d)), 'not_authenticated');
		assert.equal(calls.length, 1);
	}
});

test('statuses map to the plan assistant error kinds', async () => {
	const cases: Array<[number, unknown, string]> = [
		[403, { code: 'ai_disclosure_required' }, 'consent'],
		[403, { error: 'forbidden' }, 'unavailable'],
		[429, { error: 'daily_limit' }, 'daily_limit'],
		[400, { error: 'invalid season request' }, 'invalid'],
		[422, { error: 'could not understand request' }, 'not_understood'],
		[503, { error: 'season assistant unavailable' }, 'unavailable'],
		[500, 'not json', 'unavailable'],
	];
	for (const [status, body, kind] of cases) {
		const { d } = deps([response(status, body)]);
		assert.equal(await kindOf(sendSeasonRequest('x', '2026-10-16', d)), kind, `${status}`);
	}
});

test('a network failure is unavailable', async () => {
	const { d } = deps([new Error('offline')]);
	assert.equal(await kindOf(sendSeasonRequest('x', '2026-10-16', d)), 'unavailable');
});

test('a 200 whose body breaks the contract is unavailable, never partly shown', async () => {
	const { d } = deps([response(200, { races: [{ ...RACE, priority: 'Z' }], assumptions: [] })]);
	assert.equal(await kindOf(sendSeasonRequest('x', '2026-10-16', d)), 'unavailable');
	const { d: d2 } = deps([response(200, 'not json')]);
	assert.equal(await kindOf(sendSeasonRequest('x', '2026-10-16', d2)), 'unavailable');
});

test('parse accepts an empty list with its reasons', () => {
	assert.deepEqual(parseSeasonRequestResult({ races: [], assumptions: ['race_dropped_date'] }), {
		races: [],
		assumptions: ['race_dropped_date'],
	});
});

test('parse refuses every out-of-contract race field', () => {
	const bad: unknown[] = [
		null,
		'race',
		[],
		{ ...RACE, name: '' },
		{ ...RACE, name: 7 },
		{ ...RACE, date: '13 June' },
		{ ...RACE, date: undefined },
		{ ...RACE, distanceM: 4999 },
		{ ...RACE, distanceM: 400_001 },
		{ ...RACE, distanceM: '89000' },
		{ ...RACE, distanceM: NaN },
		{ ...RACE, priority: 'a' },
		{ ...RACE, priority: undefined },
		{ ...RACE, goalTimeSec: 0 },
		{ ...RACE, goalTimeSec: 1.5 },
		{ ...RACE, goalTimeSec: '3600' },
		{ ...RACE, goalTimeSec: undefined },
	];
	for (const race of bad) {
		assert.equal(parseSeasonRequestResult({ races: [race], assumptions: [] }), null, JSON.stringify(race));
	}
});

test('parse refuses a malformed envelope, an unknown assumption and more than 12 races', () => {
	for (const raw of [null, [], 'x', {}, { races: [] }, { assumptions: [] }, { races: {}, assumptions: [] }]) {
		assert.equal(parseSeasonRequestResult(raw), null, JSON.stringify(raw));
	}
	assert.equal(parseSeasonRequestResult({ races: [], assumptions: ['made_up'] }), null);
	assert.equal(parseSeasonRequestResult({ races: [], assumptions: [3] }), null);
	assert.equal(parseSeasonRequestResult({ races: Array(13).fill(RACE), assumptions: [] }), null);
	assert.ok(parseSeasonRequestResult({ races: Array(12).fill(RACE), assumptions: [] }));
});

test('every assumption the server can send has an English label, and an unknown one has none', () => {
	const messages = en as Record<string, string>;
	for (const a of SEASON_REQUEST_ASSUMPTIONS) {
		const key = seasonAssumptionMessageKey(a);
		assert.ok(key, a);
		assert.ok(messages[key]?.length > 0, `${a} -> ${key} has no English string`);
	}
	assert.equal(seasonAssumptionMessageKey('made_up'), null);
	assert.equal(seasonAssumptionMessageKey('toString'), null);
});
