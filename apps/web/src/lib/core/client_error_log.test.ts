import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { CLIENT_ERROR_LOG_PREFIX, logClientError } from './client_error_log.ts';

const HERE = dirname(fileURLToPath(import.meta.url));

test('logs the prefix, status, message, route and the error itself', () => {
	const calls: unknown[][] = [];
	const error = new Error('each_key_duplicate');
	logClientError(
		{ error, status: 500, message: 'Internal Error', event: { route: { id: '/dashboard' } } },
		(...data) => calls.push(data)
	);
	assert.equal(calls.length, 1);
	assert.equal(calls[0][0], CLIENT_ERROR_LOG_PREFIX);
	assert.equal(calls[0][1], '500 Internal Error on /dashboard');
	assert.equal(calls[0][2], error);
});

test('names an unmatched route instead of throwing on it', () => {
	const calls: unknown[][] = [];
	logClientError(
		{ error: 'x', status: 500, message: 'Internal Error', event: { route: { id: null } } },
		(...data) => calls.push(data)
	);
	assert.equal(calls[0][1], '500 Internal Error on (no route)');
});

test('a client-side 404 is not logged, so the crash net does not read it as a crash', () => {
	const calls: unknown[][] = [];
	logClientError(
		{ error: new Error('Not found: /nope'), status: 404, message: 'Not Found', event: { route: { id: null } } },
		(...data) => calls.push(data)
	);
	assert.equal(calls.length, 0);
});

test('a throwing sink does not escape', () => {
	assert.doesNotThrow(() =>
		logClientError({ error: 1, status: 500, message: 'm', event: {} }, () => {
			throw new Error('console is gone');
		})
	);
});

// The hook itself imports `$app/env` and Sentry, which the tsx runner cannot
// load, so its wiring is read from source like hooks_consent.test.ts does.
test('the client handleError logs locally before, and outside, the consent gate', () => {
	const src = readFileSync(resolve(HERE, '..', '..', 'hooks.client.ts'), 'utf8');
	const body = /export const handleError: HandleClientError = \(input\) => \{([\s\S]*?)\n\};/.exec(src);
	assert.ok(body, 'hooks.client.ts must export a typed handleError arrow function');
	const log = body[1].indexOf('logClientError(input)');
	const gate = body[1].indexOf('hasAcceptedConsent()');
	assert.ok(log >= 0, 'handleError must call logClientError(input)');
	assert.ok(gate >= 0, 'handleError must keep the consent gate on the Sentry path');
	assert.ok(
		log < gate,
		'logClientError must run before the consent check, or a reader who declined error ' +
			'reporting gets a 500 with nothing in DevTools'
	);
});
