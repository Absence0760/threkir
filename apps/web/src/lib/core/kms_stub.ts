// Test stub for the cold-start secret bag.
//
// Both Lambda wrapper suites drive handlers that now call `loadSecrets()`
// before they reach their core, so every one of them needs a KMS that answers.
// Installed here once rather than transcribed into each suite, which is how the
// two coach wrappers came apart on the body cap (decisions § 968).
//
// Only `kms.*.amazonaws.com` is intercepted; anything else is handed to the
// real fetch, so a suite that starts reaching the network still shows it.

import { Buffer } from 'node:buffer';

export interface KmsStub {
	/** How many Decrypt calls the stub has answered — the cold-start count. */
	calls: number;
}

/**
 * Point `loadSecrets()` at a canned bag. `mode: 'deny'` makes KMS refuse, which
 * is the fail-closed case: the handler must answer its own 503 rather than read
 * a plaintext environment variable.
 */
export function stubKms(
	bag: Record<string, string>,
	mode: 'allow' | 'deny' = 'allow',
): KmsStub {
	process.env.SECRETS_CIPHERTEXT = 'stub-ciphertext';
	process.env.AWS_REGION = 'eu-west-2';
	process.env.AWS_ACCESS_KEY_ID = 'AKIDSTUB';
	process.env.AWS_SECRET_ACCESS_KEY = 'stub-secret';
	delete process.env.SECRETS_CONTEXT;

	const stub: KmsStub = { calls: 0 };
	const real = globalThis.fetch;
	globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
		const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
		if (!/^https:\/\/kms\.[a-z0-9-]+\.amazonaws\.com\//.test(url)) return real(input, init);
		stub.calls++;
		if (mode === 'deny')
			return new Response(JSON.stringify({ __type: 'AccessDeniedException' }), { status: 400 });
		return new Response(
			JSON.stringify({
				Plaintext: Buffer.from(JSON.stringify(bag), 'utf8').toString('base64'),
			}),
			{ status: 200 },
		);
	}) as typeof fetch;
	return stub;
}
