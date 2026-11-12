import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { LambdaFunctionURLEvent } from 'aws-lambda';

import { decodeKey, handler } from '../../../lambda/share-entity/src/index';

/// `/share/club/%zz` carries a percent-escape that isn't one, so
/// `decodeURIComponent` throws a URIError. Unguarded it fell to the Lambda's
/// outer catch and answered 503 — a server error, and a retry signal telling
/// crawlers to come back for a link that will never resolve. Every other
/// unresolvable entity answers the branded `noindex` 404, and so must this.

// Configured, so a 404 below can only come from the key — not from the
// missing-Supabase-config branch that also yields one. A malformed key is
// rejected before any lookup runs, so nothing reaches the network.
process.env.PUBLIC_SUPABASE_URL = 'http://supabase.invalid';
process.env.PUBLIC_SUPABASE_ANON_KEY = 'anon';

// The bundler substitutes this into the deployed artifact; the 404 branch reads
// it since decisions § 1036, so a suite that leaves it unset gets a
// ReferenceError into the outer envelope and a 503 for every case below.
(globalThis as Record<string, unknown>).__SPA_SHELL_HTML__ =
	'<!DOCTYPE html><html><head><title>Threkir</title></head><body></body></html>';

/// A GET, because the handler gates its method since decisions § 1005 and a
/// real Function URL event always carries one. These cases are about the path.
function urlEvent(rawPath: string): LambdaFunctionURLEvent {
	return {
		rawPath,
		requestContext: { http: { method: 'GET' } },
	} as unknown as LambdaFunctionURLEvent;
}

test('decodeKey returns null on a malformed percent-escape, decodes otherwise', () => {
	assert.equal(decodeKey('%zz'), null);
	assert.equal(decodeKey('%'), null);
	assert.equal(decodeKey('%E0%A4%A'), null);
	assert.equal(decodeKey('morning%20club'), 'morning club');
	assert.equal(decodeKey('plain-slug'), 'plain-slug');
});

test('a malformed path answers the branded noindex 404, never a 5xx', async () => {
	for (const path of [
		'/share/club/%zz',
		'/share/profile/%E0%A4%A',
		'/share/race/%',
		'/share/session/%zz',
		'/share/workout/%zz',
		'/share/event/%zz',
		'/share/course/%zz/park/course',
		'/share/course/us-va/park',
	]) {
		const res = await handler(urlEvent(path));
		assert.notEqual(typeof res, 'string');
		const r = res as { statusCode: number; body?: string; headers?: Record<string, string> };
		assert.equal(r.statusCode, 404, `${path} must not answer ${r.statusCode}`);
		assert.match(r.headers?.['content-type'] ?? '', /text\/html/);
		assert.match(r.body ?? '', /name="robots" content="noindex"/);
	}
});

test('a path outside the dispatcher still answers the JSON 404', async () => {
	const res = (await handler(urlEvent('/share/nothing/abc'))) as { statusCode: number };
	assert.equal(res.statusCode, 404);
});

/// Share-link visits are counted by the page in the visitor's browser, not
/// here (decisions § 2268): CloudFront caches this HTML for five minutes and
/// strips the query string, so the Lambda would count edge misses and never
/// see a `ref`. Pinned from both sides: the handler makes no call to the
/// counter, and a `ref` in the query changes nothing it serves.
test('the handler records no share visit and serves the same answer with or without a ref', async () => {
	const realFetch = globalThis.fetch;
	const calls: string[] = [];
	globalThis.fetch = (async (input: string | URL | Request) => {
		const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
		calls.push(url);
		return new Response('[]', { status: 200, headers: { 'content-type': 'application/json' } });
	}) as typeof fetch;
	try {
		const id = '0b9f3c2e-1111-4222-8333-944455556666';
		const bare = (await handler(urlEvent(`/share/challenge/${id}`))) as { statusCode: number; body?: string };
		const withRef = (await handler({
			...urlEvent(`/share/challenge/${id}`),
			rawQueryString: 'ref=a1b2c3d4e5',
			queryStringParameters: { ref: 'a1b2c3d4e5' },
		} as LambdaFunctionURLEvent)) as { statusCode: number; body?: string };
		assert.equal(withRef.statusCode, bare.statusCode);
		assert.equal(withRef.body, bare.body);
		assert.ok(calls.length > 0, 'the lookup reached the stubbed network');
		assert.deepEqual(
			calls.filter((u) => /record_share_visit|share_link/.test(u)),
			[],
			'the Lambda must not write a share visit',
		);
	} finally {
		globalThis.fetch = realFetch;
	}
});

test('/og/challenge/<id>.png answers a cacheable PNG even when the challenge is unknown', async () => {
	const realFetch = globalThis.fetch;
	globalThis.fetch = (async () =>
		new Response('[]', { status: 200, headers: { 'content-type': 'application/json' } })) as typeof fetch;
	try {
		const res = (await handler(urlEvent('/og/challenge/0b9f3c2e-1111-4222-8333-944455556666.png'))) as {
			statusCode: number;
			isBase64Encoded?: boolean;
			body?: string;
			headers?: Record<string, string>;
		};
		assert.equal(res.statusCode, 200);
		assert.equal(res.headers?.['content-type'], 'image/png');
		assert.match(res.headers?.['cache-control'] ?? '', /max-age=\d+/);
		assert.equal(res.isBase64Encoded, true);
		const png = Buffer.from(res.body ?? '', 'base64');
		assert.ok(png.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47])));
	} finally {
		globalThis.fetch = realFetch;
	}
});
