// Both credential-carrying Lambdas refuse when the secret bag cannot be read.
//
// Its own file because the refusal has to be the FIRST thing either handler is
// asked to do: `loadSecrets()` memoises a resolved bag for the life of the
// container, so a suite that has already decrypted successfully can never
// observe this branch again. node's test runner gives each file its own
// process, which is the only clean way to hold both states.
//
// Invocation:
//   npx tsx --test src/lib/core/lambda_secret_refusal.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';

import { stubKms } from './kms_stub';

// The plaintext variables the old design used, deliberately set. If either
// handler still reads one of these, the cases below pass a key through instead
// of refusing — which is the entire failure this change exists to make
// impossible.
process.env.PUBLIC_SUPABASE_URL = 'http://supabase.invalid';
process.env.PUBLIC_SUPABASE_ANON_KEY = 'anon';
process.env.ANTHROPIC_API_KEY = 'sk-plaintext-must-not-be-read';
process.env.SUPABASE_SECRET_KEY = 'sb_secret_must_not_be_read';
process.env.GRAPHHOPPER_API_KEY = 'gh-must-not-be-read';
process.env.GRAPH_CYCLE_API_KEY = 'gc-must-not-be-read';
process.env.GRAPHHOPPER_URL = 'http://graphhopper.invalid';
delete process.env.COACH_PROVIDER;
delete process.env.OPENAI_BASE_URL;

const kms = stubKms({}, 'deny');

let written = { status: 0, body: '' };
const responseStream = {
	write(chunk: string | Uint8Array): boolean {
		written.body += typeof chunk === 'string' ? chunk : Buffer.from(chunk).toString('utf8');
		return true;
	},
	end(): void {},
};
(globalThis as unknown as { awslambda: unknown }).awslambda = {
	streamifyResponse: <T>(fn: T): T => fn,
	HttpResponseStream: {
		from(stream: typeof responseStream, metadata: { statusCode: number }) {
			written.status = metadata.statusCode;
			return stream;
		},
	},
};

const coach = (await import('../../../lambda/coach/src/index.js')) as {
	handler: (event: unknown, stream: unknown, context: unknown) => Promise<void>;
};
const generate = (await import('../../../lambda/generate-route/src/index.js')) as {
	handler: (event: unknown) => Promise<{ statusCode: number; body?: string }>;
};

function silenced<T>(fn: () => Promise<T>): Promise<T> {
	const realError = console.error;
	console.error = () => {};
	return fn().finally(() => {
		console.error = realError;
	});
}

test('the coach Lambda answers its own 503 when the bag cannot be decrypted', async () => {
	written = { status: 0, body: '' };
	await silenced(() =>
		coach.handler(
			{
				requestContext: { http: { method: 'POST' } },
				rawPath: '/api/coach',
				headers: { 'x-supabase-authorization': 'Bearer nope' },
				body: JSON.stringify({ messages: [{ role: 'user', content: 'hi' }] }),
			},
			responseStream,
			{},
		),
	);
	assert.equal(written.status, 503);
	assert.deepEqual(JSON.parse(written.body), { error: 'Coach is temporarily unavailable.' });
	// The refusal is the KMS refusal, not something further down the path: the
	// stub was asked exactly once, and it said no.
	assert.equal(kms.calls, 1);
});

test('the generate-route Lambda answers its own 503 when the bag cannot be decrypted', async () => {
	const out = await silenced(() =>
		generate.handler({
			requestContext: { http: { method: 'POST' } },
			headers: { 'x-supabase-authorization': 'Bearer nope' },
			body: JSON.stringify({ start: { lat: 51.5, lng: -0.1 }, targetDistanceM: 5000 }),
		}),
	);
	assert.equal(out.statusCode, 503);
	assert.deepEqual(JSON.parse(String(out.body)), {
		error: 'route generation is temporarily unavailable',
	});
});

test('a refusal is not memoised — every invocation re-asks KMS', () => {
	// Two handler invocations, two Decrypt attempts. If a rejected load were
	// cached the second would never have reached the stub, and the first
	// transient KMS blip would have taken the container down for its whole life.
	assert.equal(kms.calls, 2);
});
