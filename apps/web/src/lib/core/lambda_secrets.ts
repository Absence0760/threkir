// Cold-start decryption of the Lambda secret bag.
//
// The sops values used to arrive as PLAINTEXT `environment { variables }` on
// the coach and generate-route functions. Every API that returns a
// `FunctionConfiguration` returns those variables — including
// `lambda:UpdateFunctionCode`, which the release genuinely needs and calls on
// every function — so any principal that can deploy could read
// ANTHROPIC_API_KEY and SUPABASE_SECRET_KEY by uploading the same zip and
// reading the response. Terraform now puts a KMS ciphertext blob there
// instead: `GetFunctionConfiguration` still hands it out, and it is useless
// without `kms:Decrypt` on the env's secrets CMK, which only the execution
// role holds. See infra/modules/web-stack/main.tf and decisions § 1671.
//
// `kms_key_arn` on the function is deliberately NOT the mechanism. That field
// would make Lambda itself decrypt the environment, which hands the same
// plaintext back to the same callers and additionally requires the DEPLOY role
// to hold kms:Decrypt on the CMK — the grant this change exists to avoid
// (decisions § 1021, and claim 9 in scripts/check_infra_iam.mjs).
//
// Lives in src/lib/core/ rather than under lambda/ for the reason
// lambda_sentry.ts states: every directory in that tree is a function, and
// five guards read `<name>/src/index.ts`.
//
// No AWS SDK. The managed runtime's bundled SDK is not something to depend on
// across a runtime bump, and adding @aws-sdk/client-kms to apps/web would pull
// a build-time dependency tree into two bundles for one POST. KMS's Decrypt is
// a single JSON call; the only real work is SigV4, which node:crypto already
// has the primitives for.

import { createHash, createHmac } from 'node:crypto';

const ALGORITHM = 'AWS4-HMAC-SHA256';
const SERVICE = 'kms';

export interface AwsCredentials {
	accessKeyId: string;
	secretAccessKey: string;
	sessionToken?: string | undefined;
}

export interface SignedRequest {
	method: string;
	host: string;
	path: string;
	query: string;
	headers: Record<string, string>;
	body: string;
	region: string;
	service: string;
	credentials: AwsCredentials;
	/** Request time. Passed in rather than read here so the signer is a pure function. */
	now: Date;
}

function sha256Hex(input: string): string {
	return createHash('sha256').update(input, 'utf8').digest('hex');
}

function hmac(key: Buffer | string, data: string): Buffer {
	return createHmac('sha256', key).update(data, 'utf8').digest();
}

/** `20260918T134500Z` / `20260918`, which is the only date shape SigV4 accepts. */
export function amzDate(now: Date): { amz: string; stamp: string } {
	const amz = now.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
	return { amz, stamp: amz.slice(0, 8) };
}

export function signingKey(
	secretAccessKey: string,
	stamp: string,
	region: string,
	service: string,
): Buffer {
	return hmac(hmac(hmac(hmac(`AWS4${secretAccessKey}`, stamp), region), service), 'aws4_request');
}

/**
 * The `Authorization` header (and the `x-amz-date` that has to go with it) for
 * one SigV4-signed request. Exported whole rather than folded into the KMS call
 * so it can be tested against AWS's published signature vectors.
 */
export function signRequest(req: SignedRequest): Record<string, string> {
	const { amz, stamp } = amzDate(req.now);
	const headers: Record<string, string> = {
		...req.headers,
		host: req.host,
		'x-amz-date': amz,
	};
	if (req.credentials.sessionToken) headers['x-amz-security-token'] = req.credentials.sessionToken;

	const names = Object.keys(headers)
		.map((n) => n.toLowerCase())
		.sort();
	const lower = new Map(Object.entries(headers).map(([k, v]) => [k.toLowerCase(), v]));
	const canonicalHeaders = names.map((n) => `${n}:${(lower.get(n) ?? '').trim()}\n`).join('');
	const signedHeaders = names.join(';');

	const canonicalRequest = [
		req.method,
		req.path,
		req.query,
		canonicalHeaders,
		signedHeaders,
		sha256Hex(req.body),
	].join('\n');

	const scope = `${stamp}/${req.region}/${req.service}/aws4_request`;
	const stringToSign = [ALGORITHM, amz, scope, sha256Hex(canonicalRequest)].join('\n');
	const signature = hmac(
		signingKey(req.credentials.secretAccessKey, stamp, req.region, req.service),
		stringToSign,
	).toString('hex');

	return {
		...headers,
		authorization:
			`${ALGORITHM} Credential=${req.credentials.accessKeyId}/${scope}, ` +
			`SignedHeaders=${signedHeaders}, Signature=${signature}`,
	};
}

export interface KmsDecryptRequest {
	ciphertextBlob: string;
	encryptionContext: Record<string, string>;
	region: string;
	credentials: AwsCredentials;
	now: Date;
	fetchImpl: typeof fetch;
}

/** The decrypted plaintext, as KMS returned it. Throws on anything else. */
export async function kmsDecrypt(req: KmsDecryptRequest): Promise<string> {
	const host = `kms.${req.region}.amazonaws.com`;
	const body = JSON.stringify({
		CiphertextBlob: req.ciphertextBlob,
		EncryptionContext: req.encryptionContext,
	});
	const headers = signRequest({
		method: 'POST',
		host,
		path: '/',
		query: '',
		headers: {
			'content-type': 'application/x-amz-json-1.1',
			'x-amz-target': 'TrentService.Decrypt',
		},
		body,
		region: req.region,
		service: SERVICE,
		credentials: req.credentials,
		now: req.now,
	});

	const res = await req.fetchImpl(`https://${host}/`, { method: 'POST', headers, body });
	const text = await res.text();
	if (!res.ok) {
		// The KMS error TYPE is operator-actionable (AccessDeniedException vs
		// InvalidCiphertextException say different things about what to fix); the
		// message can echo request material, so it is not carried.
		let type = 'unparseable error body';
		try {
			const parsed: unknown = JSON.parse(text);
			if (parsed && typeof parsed === 'object' && '__type' in parsed)
				type = String((parsed as { __type: unknown }).__type);
		} catch {
			// keep the placeholder
		}
		throw new Error(`kms:Decrypt failed with HTTP ${res.status} (${type})`);
	}
	const parsed: unknown = JSON.parse(text);
	const plaintext =
		parsed && typeof parsed === 'object' && 'Plaintext' in parsed
			? (parsed as { Plaintext: unknown }).Plaintext
			: null;
	if (typeof plaintext !== 'string') throw new Error('kms:Decrypt returned no Plaintext');
	return Buffer.from(plaintext, 'base64').toString('utf8');
}

export interface SecretsLoaderDeps {
	env: Record<string, string | undefined>;
	fetchImpl: typeof fetch;
	now: () => Date;
}

/**
 * A loader for one function's secret bag, memoised across invocations in the
 * same container — one `kms:Decrypt` per cold start, not per request.
 *
 * Fail-closed in every direction: an absent ciphertext, absent credentials, a
 * KMS refusal or a plaintext that is not a flat string map all REJECT. There is
 * deliberately no fallback to a plaintext environment variable — a fallback
 * would leave the plaintext env in place and defeat the whole change.
 *
 * Only a resolved bag is memoised. Caching the rejected promise would let one
 * transient KMS failure poison a warm container for the rest of its life,
 * turning a blip into an outage for every request that lands on it.
 */
export function createSecretsLoader(deps: SecretsLoaderDeps): () => Promise<Record<string, string>> {
	let cached: Promise<Record<string, string>> | null = null;
	return () => {
		if (cached) return cached;
		const pending = loadOnce(deps);
		cached = pending.then(
			(bag) => bag,
			(err: unknown) => {
				cached = null;
				throw err;
			},
		);
		return cached;
	};
}

async function loadOnce(deps: SecretsLoaderDeps): Promise<Record<string, string>> {
	const ciphertextBlob = deps.env.SECRETS_CIPHERTEXT?.trim();
	if (!ciphertextBlob)
		throw new Error(
			'SECRETS_CIPHERTEXT is not set — this function has no secret bag and must refuse rather ' +
				'than read a plaintext environment variable',
		);
	const region = deps.env.AWS_REGION ?? deps.env.AWS_DEFAULT_REGION;
	const accessKeyId = deps.env.AWS_ACCESS_KEY_ID;
	const secretAccessKey = deps.env.AWS_SECRET_ACCESS_KEY;
	if (!region || !accessKeyId || !secretAccessKey)
		throw new Error('no AWS execution-role credentials in the environment');

	const plaintext = await kmsDecrypt({
		ciphertextBlob,
		encryptionContext: parseEncryptionContext(deps.env.SECRETS_CONTEXT),
		region,
		credentials: {
			accessKeyId,
			secretAccessKey,
			sessionToken: deps.env.AWS_SESSION_TOKEN,
		},
		now: deps.now(),
		fetchImpl: deps.fetchImpl,
	});

	let parsed: unknown;
	try {
		parsed = JSON.parse(plaintext);
	} catch {
		throw new Error('the decrypted secret bag is not JSON');
	}
	if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed))
		throw new Error('the decrypted secret bag is not a JSON object');
	const bag: Record<string, string> = {};
	for (const [k, v] of Object.entries(parsed)) {
		if (typeof v !== 'string') throw new Error(`secret ${k} is not a string`);
		bag[k] = v;
	}
	return bag;
}

function parseEncryptionContext(raw: string | undefined): Record<string, string> {
	if (!raw?.trim()) return {};
	const parsed: unknown = JSON.parse(raw);
	if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed))
		throw new Error('SECRETS_CONTEXT is not a JSON object');
	const out: Record<string, string> = {};
	for (const [k, v] of Object.entries(parsed)) {
		if (typeof v !== 'string') throw new Error(`SECRETS_CONTEXT.${k} is not a string`);
		out[k] = v;
	}
	return out;
}

/**
 * The process-wide loader the handlers call. `globalThis.fetch` is read at call
 * time, not captured here, so a bundle that never reaches a Lambda (a test, a
 * dev wrapper) does not fail at import.
 */
export const loadSecrets = createSecretsLoader({
	env: process.env,
	fetchImpl: (...args) => globalThis.fetch(...args),
	now: () => new Date(),
});
