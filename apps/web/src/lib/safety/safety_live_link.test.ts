import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseSafetyLinkToken } from './safety_live_link';

const T = '0b6f2c1e-4a8d-4c3b-9e7f-1a2b3c4d5e6f';

test('reads the token from the fragment', () => {
	assert.equal(parseSafetyLinkToken(`#k=${T}`), T);
	assert.equal(parseSafetyLinkToken(`k=${T}`), T);
});

test('normalises case, the database mints lowercase', () => {
	assert.equal(parseSafetyLinkToken(`#k=${T.toUpperCase()}`), T);
});

test('no fragment, an empty one or another key is no token', () => {
	assert.equal(parseSafetyLinkToken(''), null);
	assert.equal(parseSafetyLinkToken(null), null);
	assert.equal(parseSafetyLinkToken(undefined), null);
	assert.equal(parseSafetyLinkToken('#'), null);
	assert.equal(parseSafetyLinkToken(`#token=${T}`), null);
});

test('anything that is not a UUID is refused rather than sent to the server', () => {
	assert.equal(parseSafetyLinkToken('#k=not-a-token'), null);
	assert.equal(parseSafetyLinkToken(`#k=${T}x`), null);
	assert.equal(parseSafetyLinkToken(`#k=${T.slice(1)}`), null);
	assert.equal(parseSafetyLinkToken('#k=%22%3E%3Cscript%3E'), null);
});

test('other fragment params do not hide the token', () => {
	assert.equal(parseSafetyLinkToken(`#x=1&k=${T}`), T);
});

test('the token RPCs send the token in a POST body, never a GET query string', async () => {
	// A `get: true` RPC puts every argument in the request URL, which the
	// API gateway logs; the fragment kept the token out of CloudFront's logs
	// and this keeps it out of Supabase's.
	const { readFileSync } = await import('node:fs');
	const src = readFileSync('src/lib/core/data.ts', 'utf-8');
	for (const fn of ['fetchSafetyLiveRun', 'fetchSafetyLivePings']) {
		const start = src.indexOf(`export async function ${fn}`);
		assert.ok(start >= 0, `${fn} not found`);
		const next = src.indexOf('\nexport ', start + 1);
		const body = src.slice(start, next > start ? next : undefined);
		assert.ok(!/get:\s*true/.test(body), `${fn} must not use a GET RPC`);
		assert.match(body, /p_token: token/);
	}
});
