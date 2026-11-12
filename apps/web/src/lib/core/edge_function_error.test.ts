import { test } from 'node:test';
import assert from 'node:assert/strict';
import { edgeFunctionErrorCode, edgeFunctionErrorMessage } from './edge_function_error.js';

const TRANSPORT_SENTENCE = 'Edge Function returned a non-2xx status code';

/// The shape supabase-js hands back for every non-2xx: a fixed message with
/// the raw Response on `context`.
function httpError(body: BodyInit | null, init: ResponseInit = { status: 409 }) {
	const err = new Error(TRANSPORT_SENTENCE) as Error & { context: Response };
	err.context = new Response(body, init);
	return err;
}

test('edgeFunctionErrorCode reads the envelope code off the Response', async () => {
	const err = httpError(JSON.stringify({ error: 'sold_out' }));
	assert.equal(await edgeFunctionErrorCode(err), 'sold_out');
});

test('edgeFunctionErrorCode reads a clone, so the body stays readable for the next caller', async () => {
	const err = httpError(JSON.stringify({ error: 'sales_closed' }));
	assert.equal(await edgeFunctionErrorCode(err), 'sales_closed');
	assert.equal(await edgeFunctionErrorCode(err), 'sales_closed', 'a second read sees the same code');
	assert.equal(err.context.bodyUsed, false);
});

test('edgeFunctionErrorCode is null for anything that is not a string code', async () => {
	for (const body of [
		JSON.stringify({ error: 42 }),
		JSON.stringify({ error: { code: 'x' } }),
		JSON.stringify({ message: 'no error key' }),
		JSON.stringify(null),
		JSON.stringify(['sold_out']),
	]) {
		assert.equal(await edgeFunctionErrorCode(httpError(body)), null, body);
	}
});

test('edgeFunctionErrorCode is null for a non-JSON or empty error page', async () => {
	assert.equal(await edgeFunctionErrorCode(httpError('<html>502 Bad Gateway</html>', { status: 502 })), null);
	assert.equal(await edgeFunctionErrorCode(httpError(null, { status: 500 })), null);
});

test('edgeFunctionErrorCode is null for an already-consumed body instead of throwing', async () => {
	const err = httpError(JSON.stringify({ error: 'sold_out' }));
	await err.context.text();
	assert.equal(await edgeFunctionErrorCode(err), null);
});

test('edgeFunctionErrorCode is null when there is no Response to read', async () => {
	for (const err of [
		null,
		undefined,
		'boom',
		new TypeError('Failed to fetch'),
		{ context: 'not a response' },
		{ context: { status: 500 } },
	]) {
		assert.equal(await edgeFunctionErrorCode(err), null, String(err));
	}
});

test('edgeFunctionErrorMessage surfaces the envelope code over the transport sentence', async () => {
	const msg = await edgeFunctionErrorMessage(
		httpError(JSON.stringify({ error: 'host_cannot_accept_payments' })),
		'Could not start checkout',
	);
	assert.equal(msg, 'host_cannot_accept_payments');
});

test('edgeFunctionErrorMessage never shows the transport sentence for an HTTP error without a code', async () => {
	const msg = await edgeFunctionErrorMessage(
		httpError('<html>oops</html>', { status: 502 }),
		'Could not start checkout',
	);
	assert.equal(msg, 'Could not start checkout');
	assert.notEqual(msg, TRANSPORT_SENTENCE);
});

test('edgeFunctionErrorMessage keeps a real error message when there is no HTTP context', async () => {
	assert.equal(
		await edgeFunctionErrorMessage(new TypeError('Failed to fetch'), 'fallback'),
		'Failed to fetch',
		'a relay/network failure carries a message worth showing',
	);
	assert.equal(await edgeFunctionErrorMessage(new Error(''), 'fallback'), 'fallback');
	assert.equal(await edgeFunctionErrorMessage('a thrown string', 'fallback'), 'fallback');
	assert.equal(await edgeFunctionErrorMessage(null, 'fallback'), 'fallback');
});
