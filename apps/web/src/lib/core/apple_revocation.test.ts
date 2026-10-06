import { test } from 'node:test';
import assert from 'node:assert/strict';
import { appleRevocationRequest, keepAppleRevocationCredential } from './apple_revocation.js';

test('an Apple callback with a provider refresh token yields the request body', () => {
	assert.deepEqual(appleRevocationRequest('apple', { provider_refresh_token: ' r.tok ' }), {
		refresh_token: 'r.tok',
	});
});

test('a Google callback is never mistaken for Apple, though it carries a token too', () => {
	assert.equal(appleRevocationRequest('google', { provider_refresh_token: 'g.tok' }), null);
	assert.equal(appleRevocationRequest(null, { provider_refresh_token: 'g.tok' }), null);
});

test('an Apple callback with no token, a blank one or no session sends nothing', () => {
	assert.equal(appleRevocationRequest('apple', { provider_refresh_token: null }), null);
	assert.equal(appleRevocationRequest('apple', { provider_refresh_token: '  ' }), null);
	assert.equal(appleRevocationRequest('apple', null), null);
});

function fakeFunctions(result: { error: unknown } | Error) {
	const calls: { name: string; body: unknown }[] = [];
	return {
		calls,
		invoke: async (name: string, opts: { body: unknown }) => {
			calls.push({ name, body: opts.body });
			if (result instanceof Error) throw result;
			return result;
		},
	};
}

test('the token is posted to apple-token-exchange', async () => {
	const fns = fakeFunctions({ error: null });
	assert.equal(await keepAppleRevocationCredential(fns, 'apple', { provider_refresh_token: 'r' }), true);
	assert.deepEqual(fns.calls, [{ name: 'apple-token-exchange', body: { refresh_token: 'r' } }]);
});

test('nothing is posted for a non-Apple callback', async () => {
	const fns = fakeFunctions({ error: null });
	assert.equal(await keepAppleRevocationCredential(fns, 'google', { provider_refresh_token: 'g' }), false);
	assert.equal(fns.calls.length, 0);
});

test('a refused or thrown exchange answers false rather than throwing', async () => {
	const origError = console.error;
	console.error = () => {};
	try {
		const refused = fakeFunctions({ error: { message: 'apple_not_configured' } });
		assert.equal(await keepAppleRevocationCredential(refused, 'apple', { provider_refresh_token: 'r' }), false);
		const thrown = fakeFunctions(new Error('offline'));
		assert.equal(await keepAppleRevocationCredential(thrown, 'apple', { provider_refresh_token: 'r' }), false);
	} finally {
		console.error = origError;
	}
});
