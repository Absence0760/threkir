// `npx tsx --test src/lib/core/provider_error.test.ts`
//
// An AI-provider error's message (and the stack that repeats it) can quote
// the runner's own text, so only name, status and the provider's error type
// may reach a log line.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { providerErrorFields } from './provider_error';

test('an Anthropic-style API error keeps name, status and type only', () => {
	const e = Object.assign(new Error('400 {"error":{"message":"my private journal text"}}'), {
		name: 'BadRequestError',
		status: 400,
		error: { error: { type: 'invalid_request_error', message: 'my private journal text' } },
	});
	const fields = providerErrorFields(e);
	assert.deepEqual(fields, { name: 'BadRequestError', status: 400, type: 'invalid_request_error' });
	assert.ok(!JSON.stringify(fields).includes('journal'), 'no message text survives');
	assert.ok(!('message' in fields) && !('stack' in fields));
});

test('missing or mistyped fields read as unknown / null, never the raw value', () => {
	assert.deepEqual(providerErrorFields({}), { name: 'unknown', status: null, type: null });
	assert.deepEqual(providerErrorFields({ name: 42, status: '500', error: { error: { type: 7 } } }), {
		name: 'unknown',
		status: null,
		type: null,
	});
	assert.deepEqual(providerErrorFields({ name: 'TypeError', error: 'flat string' }), {
		name: 'TypeError',
		status: null,
		type: null,
	});
});

test('a non-object reports only its kind', () => {
	assert.deepEqual(providerErrorFields(null), { kind: 'object' });
	assert.deepEqual(providerErrorFields(undefined), { kind: 'undefined' });
	assert.deepEqual(providerErrorFields('the runner said something private'), { kind: 'string' });
	assert.deepEqual(providerErrorFields(503), { kind: 'number' });
});
