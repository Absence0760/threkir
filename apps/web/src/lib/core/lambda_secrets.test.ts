// The cold-start secret bag: the signer, the KMS call, and every fail-closed edge.
//
// Invocation:
//   npx tsx --test src/lib/core/lambda_secrets.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	amzDate,
	createSecretsLoader,
	kmsDecrypt,
	signRequest,
	signingKey,
} from './lambda_secrets';

// AWS's own published example for deriving a SigV4 signing key. The point of
// pinning a vector we did not compute is that it fails if this file's HMAC
// chain is wrong in any way — order, the AWS4 prefix, the terminator.
const AWS_EXAMPLE_SECRET = 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY';

function kmsResponse(payload: unknown, status = 200): typeof fetch {
	return (async () =>
		new Response(JSON.stringify(payload), { status })) as unknown as typeof fetch;
}

function bagCiphertext(bag: unknown): unknown {
	return { Plaintext: Buffer.from(JSON.stringify(bag), 'utf8').toString('base64') };
}

test('the signing-key chain matches the AWS documentation vector', () => {
	assert.equal(
		signingKey(AWS_EXAMPLE_SECRET, '20150830', 'us-east-1', 'iam').toString('hex'),
		'c4afb1cc5771d871763a393e44b703571b55cc28424d1a5e86da6ed3c154a4b9',
	);
});

test('a signed request matches the AWS sigv4 get-vanilla test-suite signature', () => {
	// The suite's `get-vanilla` case: GET / with Host and X-Amz-Date only.
	const headers = signRequest({
		method: 'GET',
		host: 'example.amazonaws.com',
		path: '/',
		query: '',
		headers: {},
		body: '',
		region: 'us-east-1',
		service: 'service',
		credentials: { accessKeyId: 'AKIDEXAMPLE', secretAccessKey: AWS_EXAMPLE_SECRET },
		now: new Date('2015-08-30T12:36:00.000Z'),
	});
	assert.equal(
		headers.authorization,
		'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, ' +
			'SignedHeaders=host;x-amz-date, ' +
			'Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31',
	);
});

test('amzDate drops the separators and the milliseconds', () => {
	assert.deepEqual(amzDate(new Date('2026-09-18T13:45:06.789Z')), {
		amz: '20260918T134506Z',
		stamp: '20260918',
	});
});

test('a session token is signed, not merely sent', () => {
	const headers = signRequest({
		method: 'POST',
		host: 'kms.eu-west-2.amazonaws.com',
		path: '/',
		query: '',
		headers: { 'content-type': 'application/x-amz-json-1.1' },
		body: '{}',
		region: 'eu-west-2',
		service: 'kms',
		credentials: { accessKeyId: 'AKID', secretAccessKey: 'sec', sessionToken: 'tok' },
		now: new Date('2026-09-18T00:00:00.000Z'),
	});
	// A token sent but left out of SignedHeaders is the failure that reads as a
	// credential problem: KMS answers 403 and the header is right there.
	assert.match(headers.authorization, /SignedHeaders=content-type;host;x-amz-date;x-amz-security-token/);
	assert.equal(headers['x-amz-security-token'], 'tok');
});

test('kmsDecrypt sends the Decrypt target, the blob and the encryption context', async () => {
	let seen: { url: string; init: RequestInit } | null = null;
	const fetchImpl = (async (url: string, init: RequestInit) => {
		seen = { url, init };
		return new Response(JSON.stringify(bagCiphertext({ A: '1' })), { status: 200 });
	}) as unknown as typeof fetch;

	const plaintext = await kmsDecrypt({
		ciphertextBlob: 'BLOB',
		encryptionContext: { function: 'threkir-web-prod-coach' },
		region: 'eu-west-2',
		credentials: { accessKeyId: 'AKID', secretAccessKey: 'sec' },
		now: new Date('2026-09-18T00:00:00.000Z'),
		fetchImpl,
	});

	assert.equal(plaintext, '{"A":"1"}');
	assert.ok(seen);
	const call = seen as unknown as { url: string; init: { headers: Record<string, string>; body: string } };
	assert.equal(call.url, 'https://kms.eu-west-2.amazonaws.com/');
	assert.equal(call.init.headers['x-amz-target'], 'TrentService.Decrypt');
	assert.deepEqual(JSON.parse(call.init.body), {
		CiphertextBlob: 'BLOB',
		EncryptionContext: { function: 'threkir-web-prod-coach' },
	});
});

test('a KMS refusal throws with the error type and never the message', async () => {
	await assert.rejects(
		kmsDecrypt({
			ciphertextBlob: 'BLOB',
			encryptionContext: {},
			region: 'eu-west-2',
			credentials: { accessKeyId: 'AKID', secretAccessKey: 'sec' },
			now: new Date(),
			fetchImpl: kmsResponse(
				{ __type: 'AccessDeniedException', message: 'ciphertext for threkir-web-prod' },
				400,
			),
		}),
		(e: Error) => {
			assert.match(e.message, /HTTP 400 \(AccessDeniedException\)/);
			assert.doesNotMatch(e.message, /threkir-web-prod/);
			return true;
		},
	);
});

const ENV = {
	SECRETS_CIPHERTEXT: 'BLOB',
	AWS_REGION: 'eu-west-2',
	AWS_ACCESS_KEY_ID: 'AKID',
	AWS_SECRET_ACCESS_KEY: 'sec',
	AWS_SESSION_TOKEN: 'tok',
};

test('the bag is decrypted once per container, not once per call', async () => {
	let calls = 0;
	const load = createSecretsLoader({
		env: { ...ENV },
		fetchImpl: (async () => {
			calls++;
			return new Response(JSON.stringify(bagCiphertext({ ANTHROPIC_API_KEY: 'sk-x' })), {
				status: 200,
			});
		}) as unknown as typeof fetch,
		now: () => new Date(),
	});
	const [a, b, c] = await Promise.all([load(), load(), load()]);
	assert.deepEqual(a, { ANTHROPIC_API_KEY: 'sk-x' });
	assert.equal(b, a);
	assert.equal(c, a);
	assert.equal(await load(), a);
	assert.equal(calls, 1);
});

test('an absent ciphertext refuses rather than falling back to a plaintext env var', async () => {
	const load = createSecretsLoader({
		// The plaintext variable the old design used is deliberately present: the
		// whole point of the change is that this is not a source any more.
		env: { ...ENV, SECRETS_CIPHERTEXT: '', ANTHROPIC_API_KEY: 'sk-plaintext' },
		fetchImpl: kmsResponse(bagCiphertext({})),
		now: () => new Date(),
	});
	await assert.rejects(load(), /SECRETS_CIPHERTEXT is not set/);
});

test('missing execution-role credentials refuse', async () => {
	for (const missing of ['AWS_REGION', 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY']) {
		const env: Record<string, string | undefined> = { ...ENV };
		delete env[missing];
		const load = createSecretsLoader({
			env,
			fetchImpl: kmsResponse(bagCiphertext({ A: '1' })),
			now: () => new Date(),
		});
		await assert.rejects(load(), /no AWS execution-role credentials/, missing);
	}
});

test('a decrypted bag that is not a flat string map refuses', async () => {
	for (const bad of ['[]', '"x"', '{"A":1}', '{"A":null}', 'not json']) {
		const load = createSecretsLoader({
			env: { ...ENV },
			fetchImpl: kmsResponse({
				Plaintext: Buffer.from(bad, 'utf8').toString('base64'),
			}),
			now: () => new Date(),
		});
		await assert.rejects(load(), bad);
	}
});

test('a transient KMS failure is not memoised, so the next invocation retries', async () => {
	let calls = 0;
	const load = createSecretsLoader({
		env: { ...ENV },
		fetchImpl: (async () => {
			calls++;
			return calls === 1
				? new Response(JSON.stringify({ __type: 'KMSInternalException' }), { status: 500 })
				: new Response(JSON.stringify(bagCiphertext({ A: '1' })), { status: 200 });
		}) as unknown as typeof fetch,
		now: () => new Date(),
	});
	await assert.rejects(load(), /HTTP 500/);
	assert.deepEqual(await load(), { A: '1' });
	assert.equal(calls, 2);
});

test('a malformed SECRETS_CONTEXT refuses rather than decrypting without one', async () => {
	const load = createSecretsLoader({
		env: { ...ENV, SECRETS_CONTEXT: '{"function":3}' },
		fetchImpl: kmsResponse(bagCiphertext({ A: '1' })),
		now: () => new Date(),
	});
	await assert.rejects(load(), /SECRETS_CONTEXT\.function is not a string/);
});

test('SECRETS_CONTEXT reaches the Decrypt call verbatim', async () => {
	let body = '';
	const load = createSecretsLoader({
		env: { ...ENV, SECRETS_CONTEXT: '{"function":"threkir-web-prod-generate-route"}' },
		fetchImpl: (async (_url: string, init: { body: string }) => {
			body = init.body;
			return new Response(JSON.stringify(bagCiphertext({ A: '1' })), { status: 200 });
		}) as unknown as typeof fetch,
		now: () => new Date(),
	});
	await load();
	assert.deepEqual(JSON.parse(body).EncryptionContext, {
		function: 'threkir-web-prod-generate-route',
	});
});
