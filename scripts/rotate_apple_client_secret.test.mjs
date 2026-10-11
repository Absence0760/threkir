import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { createHash, generateKeyPairSync, verify } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	APPLE_AUDIENCE,
	MAX_LIFETIME_S,
	REQUIRED_ENV,
	SERVICES_ID,
	buildClientSecret,
	describeReadBack,
	firstClientId,
	holdsSecret,
	missingEnv,
	normalizePem,
	rotate,
} from './rotate_apple_client_secret.mjs';

/**
 * Every key here is generated in the test, so no real credential is read. The
 * signature is checked with Node's own verifier in JWS (ieee-p1363) form,
 * which is the encoding Apple checks and the one Node does not emit by default.
 */

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const PEM = /** @type {string} */ (privateKey.export({ type: 'pkcs8', format: 'pem' }));
const TEAM = 'ABCDE12345';
const KID = 'KEY1234567';
const NOW = 1_800_000_000;

/** @param {string} jwt */
function decode(jwt) {
	const [h, c, s] = jwt.split('.');
	return {
		header: JSON.parse(Buffer.from(h, 'base64url').toString()),
		claims: JSON.parse(Buffer.from(c, 'base64url').toString()),
		signingInput: `${h}.${c}`,
		signature: Buffer.from(s, 'base64url'),
	};
}

test('the client secret is an ES256 JWT carrying exactly the claims Apple checks', () => {
	const { jwt, expiresAtS } = buildClientSecret({ teamId: TEAM, keyId: KID, privateKeyPem: PEM, nowS: NOW });
	const { header, claims, signingInput, signature } = decode(jwt);
	assert.deepEqual(header, { alg: 'ES256', kid: KID, typ: 'JWT' });
	assert.deepEqual(claims, { iss: TEAM, iat: NOW, exp: expiresAtS, aud: APPLE_AUDIENCE, sub: SERVICES_ID });
	assert.equal(SERVICES_ID, 'com.threkir.web');
	assert.ok(claims.exp - claims.iat <= MAX_LIFETIME_S, 'exp - iat exceeds Apple\'s six-month cap');
	assert.ok(claims.exp - claims.iat > 150 * 24 * 3600, 'a lifetime this short would lapse between monthly runs with no margin');
	assert.equal(signature.length, 64, 'ES256 needs the raw 64-byte r||s signature, not DER');
	assert.ok(
		verify('sha256', Buffer.from(signingInput), { key: publicKey, dsaEncoding: 'ieee-p1363' }, signature),
		'the signature does not verify against the signing key',
	);
});

test('a lifetime over Apple\'s cap is refused rather than clamped', () => {
	assert.equal(MAX_LIFETIME_S, 15777000);
	assert.throws(
		() => buildClientSecret({ teamId: TEAM, keyId: KID, privateKeyPem: PEM, nowS: NOW, lifetimeS: MAX_LIFETIME_S + 1 }),
		/six-month cap/,
	);
	const { jwt } = buildClientSecret({ teamId: TEAM, keyId: KID, privateKeyPem: PEM, nowS: NOW, lifetimeS: MAX_LIFETIME_S });
	assert.equal(decode(jwt).claims.exp - NOW, MAX_LIFETIME_S);
});

test('bad inputs name themselves and never echo the key', () => {
	assert.throws(() => buildClientSecret({ teamId: 'short', keyId: KID, privateKeyPem: PEM, nowS: NOW }), /APPLE_TEAM_ID/);
	assert.throws(() => buildClientSecret({ teamId: TEAM, keyId: 'lower12345', privateKeyPem: PEM, nowS: NOW }), /APPLE_SIWA_KEY_ID/);
	const notAKey = 'not a pem at all';
	assert.throws(
		() => buildClientSecret({ teamId: TEAM, keyId: KID, privateKeyPem: notAKey, nowS: NOW }),
		(err) => err instanceof Error && /APPLE_SIWA_PRIVATE_KEY/.test(err.message) && !err.message.includes(notAKey),
	);
	const rsa = generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey.export({ type: 'pkcs8', format: 'pem' });
	assert.throws(
		() => buildClientSecret({ teamId: TEAM, keyId: KID, privateKeyPem: String(rsa), nowS: NOW }),
		(err) => err instanceof Error && /P-256/.test(err.message) && !err.message.includes('PRIVATE KEY'),
	);
});

test('a PEM that lost its line breaks to escaping still signs; a real one is untouched', () => {
	const escaped = PEM.trim().replace(/\n/g, '\\n');
	assert.equal(normalizePem(escaped), PEM.trim());
	assert.equal(normalizePem(PEM), PEM.trim());
	buildClientSecret({ teamId: TEAM, keyId: KID, privateKeyPem: escaped, nowS: NOW });
});

test('missingEnv names every unset or blank secret, in order', () => {
	assert.deepEqual(missingEnv({}), REQUIRED_ENV);
	const full = Object.fromEntries(REQUIRED_ENV.map((k) => [k, 'x']));
	assert.deepEqual(missingEnv(full), []);
	assert.deepEqual(missingEnv({ ...full, APPLE_SIWA_KEY_ID: '  ' }), ['APPLE_SIWA_KEY_ID']);
});

test('firstClientId reads the comma-separated list the dashboard writes', () => {
	assert.equal(firstClientId('com.threkir.web,com.threkir.app'), 'com.threkir.web');
	assert.equal(firstClientId(' com.threkir.web , com.threkir.app'), 'com.threkir.web');
	assert.equal(firstClientId('com.threkir.app,com.threkir.web'), 'com.threkir.app');
	assert.equal(firstClientId(null), '');
});

const ENV = {
	APPLE_TEAM_ID: TEAM,
	APPLE_SIWA_KEY_ID: KID,
	APPLE_SIWA_PRIVATE_KEY: PEM,
	SUPABASE_ACCESS_TOKEN: 'test-access-token',
	SUPABASE_PROJECT_REF: 'abcdefghijklmnopqrst',
};

/**
 * A stand-in Management API holding one auth config. `failOn` makes the
 * named method answer with that status; the body it returns then carries a
 * sentinel the error message must not repeat.
 *
 * @param {{ config?: Record<string, unknown>, failOn?: { method: string, status: number }, ignorePatch?: boolean, readBack?: (stored: unknown) => unknown }} [opts]
 */
function fakeApi({ config, failOn, ignorePatch = false, readBack } = {}) {
	/** @type {Record<string, unknown>} */
	const state = {
		external_apple_enabled: true,
		external_apple_client_id: 'com.threkir.web,com.threkir.app',
		external_apple_secret: 'old',
		external_google_secret: 'SENTINEL-OTHER-SECRET',
		...config,
	};
	/** @type {{ url: string, method: string, headers: Record<string, string>, body?: string }[]} */
	const calls = [];
	/** @type {import('./rotate_apple_client_secret.mjs').Fetcher} */
	const fetcher = async (url, init) => {
		calls.push({ url, ...init });
		if (failOn && failOn.method === init.method) {
			return { ok: false, status: failOn.status, json: async () => ({ message: 'SENTINEL-OTHER-SECRET' }) };
		}
		if (init.method === 'PATCH' && !ignorePatch) Object.assign(state, JSON.parse(init.body ?? '{}'));
		const view = { ...state };
		if (readBack && init.method === 'GET') view.external_apple_secret = readBack(state.external_apple_secret);
		return { ok: true, status: 200, json: async () => view };
	};
	return { fetcher, calls, state };
}

test('rotate writes only external_apple_secret, then reads it back', async () => {
	const api = fakeApi();
	const { expiresAtS } = await rotate({ env: ENV, fetcher: api.fetcher, nowS: NOW });
	assert.deepEqual(api.calls.map((c) => c.method), ['GET', 'PATCH', 'GET']);
	for (const call of api.calls) {
		assert.equal(call.url, 'https://api.supabase.com/v1/projects/abcdefghijklmnopqrst/config/auth');
		assert.equal(call.headers.Authorization, 'Bearer test-access-token');
	}
	const body = JSON.parse(api.calls[1].body ?? '{}');
	assert.deepEqual(Object.keys(body), ['external_apple_secret'], 'the PATCH must not touch the client ids or anything else');
	assert.equal(api.state.external_apple_client_id, 'com.threkir.web,com.threkir.app');
	assert.equal(decode(String(api.state.external_apple_secret)).claims.exp, expiresAtS);
});

test('rotate fails closed, naming every missing secret, before any request', async () => {
	const api = fakeApi();
	await assert.rejects(
		rotate({ env: { ...ENV, APPLE_SIWA_PRIVATE_KEY: '', APPLE_TEAM_ID: undefined }, fetcher: api.fetcher, nowS: NOW }),
		/APPLE_TEAM_ID, APPLE_SIWA_PRIVATE_KEY/,
	);
	assert.equal(api.calls.length, 0);
});

test('rotate refuses to write when the web Services ID is not the first client id', async () => {
	const api = fakeApi({ config: { external_apple_client_id: 'com.threkir.app' } });
	await assert.rejects(rotate({ env: ENV, fetcher: api.fetcher, nowS: NOW }), /first Client ID is not com\.threkir\.web/);
	assert.deepEqual(api.calls.map((c) => c.method), ['GET']);
	assert.equal(api.state.external_apple_secret, 'old');
});

test('rotate refuses to write when the Apple provider is disabled', async () => {
	const api = fakeApi({ config: { external_apple_enabled: false } });
	await assert.rejects(rotate({ env: ENV, fetcher: api.fetcher, nowS: NOW }), /disabled/);
	assert.deepEqual(api.calls.map((c) => c.method), ['GET']);
});

for (const [method, status] of /** @type {const} */ ([['GET', 401], ['PATCH', 500]])) {
	test(`a ${status} on ${method} fails with the status and none of the response body`, async () => {
		const api = fakeApi({ failOn: { method, status } });
		await assert.rejects(
			rotate({ env: ENV, fetcher: api.fetcher, nowS: NOW }),
			(err) => err instanceof Error && err.message.includes(`HTTP ${status}`) && !err.message.includes('SENTINEL'),
		);
	});
}

test('a read-back of the secret as its SHA-256 digest confirms the write', async () => {
	const api = fakeApi({ readBack: (v) => createHash('sha256').update(String(v)).digest('hex') });
	await rotate({ env: ENV, fetcher: api.fetcher, nowS: NOW });
	assert.deepEqual(api.calls.map((c) => c.method), ['GET', 'PATCH', 'GET']);
});

test('holdsSecret accepts the value or its digest and nothing else', () => {
	const digest = createHash('sha256').update('s3cret').digest('hex');
	assert.equal(holdsSecret('s3cret', 's3cret'), true);
	assert.equal(holdsSecret(digest, 's3cret'), true);
	assert.equal(holdsSecret(digest.toUpperCase(), 's3cret'), true);
	assert.equal(holdsSecret(createHash('sha256').update('other').digest('hex'), 's3cret'), false);
	assert.equal(holdsSecret('******', 's3cret'), false);
	assert.equal(holdsSecret(undefined, 's3cret'), false);
});

test('a failed read-back is described by shape, never by content', async () => {
	const api = fakeApi({ readBack: () => 'SENTINEL-READ-BACK' });
	await assert.rejects(
		rotate({ env: ENV, fetcher: api.fetcher, nowS: NOW }),
		(err) => err instanceof Error && /18-character string/.test(err.message) && !err.message.includes('SENTINEL'),
	);
	assert.equal(describeReadBack(''), 'empty');
	assert.equal(describeReadBack('****'), 'masked');
	assert.equal(describeReadBack('a'.repeat(64)), 'as a SHA-256 digest of a different value');
});

test('a write the API accepted but did not apply is a failure, not a rotation', async () => {
	const api = fakeApi({ ignorePatch: true });
	await assert.rejects(rotate({ env: ENV, fetcher: api.fetcher, nowS: NOW }), /does not hold the secret/);
});

test('the workflow runs this script and wires every secret it reads', () => {
	const wf = readFileSync(resolve(root, '.github/workflows/rotate-apple-client-secret.yml'), 'utf8');
	assert.match(wf, /node scripts\/rotate_apple_client_secret\.mjs/);
	for (const name of REQUIRED_ENV) {
		assert.match(wf, new RegExp(`${name}: \\$\\{\\{ secrets\\.${name} \\}\\}`), `${name} is not passed to the rotation step`);
	}
	assert.match(wf, /environment: apple-secret-rotation/);
	assert.doesNotMatch(wf, /environment: production/, 'production requires a reviewer, which would stall every scheduled run');
});
