#!/usr/bin/env node
// Regenerates the Sign in with Apple OAuth client secret and writes it into
// the production Supabase project's auth config.
//
// Supabase's Apple provider authenticates the web flow to Apple with an ES256
// JWT signed by the Sign-in-with-Apple `.p8` key, and Apple refuses any such
// JWT older than six months. When it lapses every web Apple sign-in fails with
// `invalid_client` on a configuration that is otherwise correct, and nothing in
// our logs tells it apart from a misconfiguration. `rotate-apple-client-secret.yml`
// runs this monthly, so a fresh secret is always five months from expiry.
// decisions.md § 1824; the operator side is docs/ops/apple_provisioning.md § 9.
//
// Reads (all required; the first missing one is named, never its value):
//   APPLE_TEAM_ID            the 10-character Apple Developer Team ID (`iss`)
//   APPLE_SIWA_KEY_ID        the Sign-in-with-Apple key's 10-character Key ID (`kid`)
//   APPLE_SIWA_PRIVATE_KEY   that key's `.p8` file contents, PEM as is
//   SUPABASE_ACCESS_TOKEN    a Supabase personal access token (Management API)
//   SUPABASE_PROJECT_REF     the production project ref
//
// Nothing secret is ever printed: not the key, not the JWT, and not a
// Management API response body, because the auth config it returns holds
// every provider's secret. Failures name a status code and what to check.
//
// Usage: node scripts/rotate_apple_client_secret.mjs
import { createHash, createPrivateKey, sign } from 'node:crypto';
import { fileURLToPath } from 'node:url';

/** The Services ID the web flow presents to Apple; it is the JWT's `sub`. */
export const SERVICES_ID = 'com.threkir.web';

/** The audience Apple requires on a client secret. */
export const APPLE_AUDIENCE = 'https://appleid.apple.com';

/** Apple's ceiling on `exp - iat`, in seconds (six months). */
export const MAX_LIFETIME_S = 15777000;

/**
 * What this script asks for: 180 days, a day and a half inside the ceiling so
 * a runner clock running ahead of Apple's cannot push it over.
 */
export const DEFAULT_LIFETIME_S = 180 * 24 * 60 * 60;

export const MANAGEMENT_API = 'https://api.supabase.com';

/** Every environment variable the rotation reads, in the order they are checked. */
export const REQUIRED_ENV = [
	'APPLE_TEAM_ID',
	'APPLE_SIWA_KEY_ID',
	'APPLE_SIWA_PRIVATE_KEY',
	'SUPABASE_ACCESS_TOKEN',
	'SUPABASE_PROJECT_REF',
];

const APPLE_ID_PATTERN = /^[A-Z0-9]{10}$/;

/**
 * @param {Record<string, string | undefined>} env
 * @returns {string[]} the names in REQUIRED_ENV that are unset or blank
 */
export function missingEnv(env) {
	return REQUIRED_ENV.filter((name) => !(env[name] ?? '').trim());
}

/** @param {string | Buffer} value */
function base64url(value) {
	return Buffer.from(value).toString('base64url');
}

/**
 * A secret pasted through a JSON round trip can arrive with literal `\n`
 * sequences instead of line breaks; a PEM with no real newline is never
 * valid, so that is the only case rewritten.
 *
 * @param {string} pem
 */
export function normalizePem(pem) {
	const trimmed = pem.trim();
	return trimmed.includes('\n') ? trimmed : trimmed.replace(/\\n/g, '\n');
}

/**
 * @typedef {{
 *   teamId: string,
 *   keyId: string,
 *   privateKeyPem: string,
 *   servicesId?: string,
 *   nowS: number,
 *   lifetimeS?: number,
 * }} ClientSecretInput
 */

/**
 * Builds Apple's client secret: an ES256 JWT whose signature is the raw
 * 64-byte r||s pair JWS requires, not the DER encoding Node emits by default.
 * Every error message names the input at fault and none echoes its value.
 *
 * @param {ClientSecretInput} input
 * @returns {{ jwt: string, expiresAtS: number }}
 */
export function buildClientSecret({
	teamId,
	keyId,
	privateKeyPem,
	servicesId = SERVICES_ID,
	nowS,
	lifetimeS = DEFAULT_LIFETIME_S,
}) {
	if (!APPLE_ID_PATTERN.test(teamId)) {
		throw new Error('APPLE_TEAM_ID is not a 10-character Apple Team ID (uppercase letters and digits).');
	}
	if (!APPLE_ID_PATTERN.test(keyId)) {
		throw new Error('APPLE_SIWA_KEY_ID is not a 10-character Apple Key ID (uppercase letters and digits).');
	}
	if (!Number.isInteger(nowS) || nowS <= 0) {
		throw new Error('The issue time must be a positive whole number of seconds.');
	}
	if (!Number.isInteger(lifetimeS) || lifetimeS <= 0 || lifetimeS > MAX_LIFETIME_S) {
		throw new Error(`The lifetime must be between 1 and ${MAX_LIFETIME_S} seconds, Apple's six-month cap.`);
	}

	let key;
	try {
		key = createPrivateKey(normalizePem(privateKeyPem));
	} catch {
		throw new Error('APPLE_SIWA_PRIVATE_KEY is not a readable PEM private key. It should be the .p8 file contents, unmodified.');
	}
	if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
		throw new Error('APPLE_SIWA_PRIVATE_KEY is not a P-256 EC key, which every Apple .p8 is. Check it is the Sign-in-with-Apple key, not another file.');
	}

	const expiresAtS = nowS + lifetimeS;
	const header = { alg: 'ES256', kid: keyId, typ: 'JWT' };
	const claims = { iss: teamId, iat: nowS, exp: expiresAtS, aud: APPLE_AUDIENCE, sub: servicesId };
	const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;
	const signature = sign('sha256', Buffer.from(signingInput), { key, dsaEncoding: 'ieee-p1363' });
	return { jwt: `${signingInput}.${base64url(signature)}`, expiresAtS };
}

/**
 * The first entry of Supabase's comma-separated Apple client id list, which is
 * the one the web (OAuth) flow uses.
 *
 * @param {unknown} value
 * @returns {string}
 */
export function firstClientId(value) {
	if (typeof value !== 'string') return '';
	return value.split(',')[0]?.trim() ?? '';
}

/**
 * @typedef {(url: string, init: { method: string, headers: Record<string, string>, body?: string }) =>
 *   Promise<{ ok: boolean, status: number, json: () => Promise<unknown> }>} Fetcher
 */

/**
 * @typedef {{
 *   env: Record<string, string | undefined>,
 *   fetcher: Fetcher,
 *   nowS: number,
 * }} RotateInput
 */

/**
 * Reads the auth config, refuses to write a secret the web flow would not use,
 * writes the new secret, and reads it back.
 *
 * @param {RotateInput} input
 * @returns {Promise<{ expiresAtS: number }>}
 */
export async function rotate({ env, fetcher, nowS }) {
	const missing = missingEnv(env);
	if (missing.length) {
		throw new Error(
			`These secrets are unset: ${missing.join(', ')}. The header of .github/workflows/rotate-apple-client-secret.yml says what each one is and which environment holds it.`,
		);
	}
	const ref = /** @type {string} */ (env.SUPABASE_PROJECT_REF).trim();
	const url = `${MANAGEMENT_API}/v1/projects/${encodeURIComponent(ref)}/config/auth`;
	const headers = {
		Authorization: `Bearer ${/** @type {string} */ (env.SUPABASE_ACCESS_TOKEN).trim()}`,
		'Content-Type': 'application/json',
	};

	const { jwt, expiresAtS } = buildClientSecret({
		teamId: /** @type {string} */ (env.APPLE_TEAM_ID).trim(),
		keyId: /** @type {string} */ (env.APPLE_SIWA_KEY_ID).trim(),
		privateKeyPem: /** @type {string} */ (env.APPLE_SIWA_PRIVATE_KEY),
		nowS,
	});

	const before = await fetcher(url, { method: 'GET', headers });
	if (!before.ok) {
		throw new Error(
			`Reading the auth config failed with HTTP ${before.status}. A 401 or 403 is SUPABASE_ACCESS_TOKEN (expired, revoked, or not a member of the project); a 404 is SUPABASE_PROJECT_REF.`,
		);
	}
	const config = /** @type {Record<string, unknown>} */ (await before.json());
	if (config.external_apple_enabled !== true) {
		throw new Error('The Supabase Apple provider is disabled, so there is nothing to rotate for. Enable it (apple_provisioning.md § 9) before this job can do anything.');
	}
	if (firstClientId(config.external_apple_client_id) !== SERVICES_ID) {
		throw new Error(
			`The Apple provider's first Client ID is not ${SERVICES_ID}, so the web flow would not present the secret this job signs. Put ${SERVICES_ID} first in Client IDs (apple_provisioning.md § 9); this job never edits that field.`,
		);
	}

	const patch = await fetcher(url, {
		method: 'PATCH',
		headers,
		body: JSON.stringify({ external_apple_secret: jwt }),
	});
	if (!patch.ok) {
		throw new Error(
			`Writing the new client secret failed with HTTP ${patch.status}. The old secret is still in place and expires on its own schedule; rerun this workflow once the cause is fixed.`,
		);
	}

	const after = await fetcher(url, { method: 'GET', headers });
	if (!after.ok) {
		throw new Error(`The write returned success, but reading it back failed with HTTP ${after.status}, so the rotation is unconfirmed.`);
	}
	const written = /** @type {Record<string, unknown>} */ (await after.json());
	if (!holdsSecret(written.external_apple_secret, jwt)) {
		throw new Error(
			`The write returned success, but the auth config does not hold the secret this run generated (it reads back ${describeReadBack(written.external_apple_secret)}). Something else wrote it, or the API ignored the field.`,
		);
	}
	return { expiresAtS };
}

/**
 * The Management API reads a secret setting back as its SHA-256 hex digest
 * rather than the value (the same form `supabase secrets list` prints), so the
 * read-back proves the write when it is either the value or that digest.
 *
 * @param {unknown} readBack
 * @param {string} secret
 */
export function holdsSecret(readBack, secret) {
	if (typeof readBack !== 'string') return false;
	return readBack === secret || readBack.toLowerCase() === createHash('sha256').update(secret).digest('hex');
}

/**
 * The shape of a read-back that failed {@link holdsSecret}, never its content.
 *
 * @param {unknown} readBack
 */
export function describeReadBack(readBack) {
	if (readBack === undefined || readBack === null || readBack === '') return 'empty';
	if (typeof readBack !== 'string') return `as a ${typeof readBack}`;
	if (/^[0-9a-f]{64}$/i.test(readBack)) return 'as a SHA-256 digest of a different value';
	if (/^\*+$/.test(readBack)) return 'masked';
	return `as a ${readBack.length}-character string that is neither this secret nor its digest`;
}

async function main() {
	try {
		const { expiresAtS } = await rotate({
			env: process.env,
			fetcher: (url, init) => fetch(url, init),
			nowS: Math.floor(Date.now() / 1000),
		});
		console.log(`Apple OAuth client secret rotated for ${SERVICES_ID}; it expires ${new Date(expiresAtS * 1000).toISOString()}.`);
	} catch (err) {
		console.log(`::error::${err instanceof Error ? err.message : 'The rotation failed for a reason it did not name.'}`);
		process.exit(1);
	}
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
	await main();
}
