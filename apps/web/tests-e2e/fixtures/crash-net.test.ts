import assert from 'node:assert/strict';
import { test } from 'node:test';

import { CLIENT_ERROR_LOG_PREFIX } from '../../src/lib/core/client_error_log.ts';

import {
	classifyConsole,
	describeCrash,
	ERROR_BOUNDARY_MARKER,
	githubWarning,
	resolveMode,
	settle,
	validateOptions,
	type Crash
} from './crash-net.ts';

test('a Svelte runtime error at error level is a crash', () => {
	assert.equal(
		classifyConsole('error', 'Uncaught Svelte error: each_key_duplicate\nhttps://svelte.dev/e/each_key_duplicate'),
		'svelte-runtime'
	);
	assert.equal(
		classifyConsole('error', 'https://svelte.dev/e/kit/app_stores_removed'),
		'svelte-runtime'
	);
});

test('a Svelte warning links the same docs and is not a crash', () => {
	assert.equal(classifyConsole('warning', 'https://svelte.dev/e/state_snapshot_uncloneable'), null);
	assert.equal(classifyConsole('log', 'https://svelte.dev/e/each_key_duplicate'), null);
});

test('an ordinary console error is not a crash', () => {
	assert.equal(classifyConsole('error', 'Failed to load resource: 404'), null);
	assert.equal(classifyConsole('error', 'see svelte.dev/docs for help'), null);
});

test('the client handleError log line and the boundary marker are crashes', () => {
	assert.equal(classifyConsole('error', `${CLIENT_ERROR_LOG_PREFIX} 500 Internal Error on /dashboard`), 'client-error');
	assert.equal(classifyConsole('error', `${ERROR_BOUNDARY_MARKER} (500) at /dashboard`), 'error-boundary');
	assert.equal(classifyConsole('info', `${CLIENT_ERROR_LOG_PREFIX} 500`), null);
});

test('mode: unset or "fail" fails, "report" reports, and anything else throws', () => {
	assert.equal(resolveMode(undefined), 'fail');
	assert.equal(resolveMode(''), 'fail');
	assert.equal(resolveMode('fail'), 'fail');
	assert.equal(resolveMode('report'), 'report');
	assert.throws(() => resolveMode('reprot'), /CRASH_NET must be/);
	assert.throws(() => resolveMode('off'), /CRASH_NET must be/);
});

test('mode: a per-test override beats the env', () => {
	assert.equal(resolveMode('report', 'fail'), 'fail');
	assert.equal(resolveMode(undefined, 'report'), 'report');
});

test('off needs a non-empty reason', () => {
	assert.doesNotThrow(() => validateOptions({ off: 'drives the 500 page on purpose' }));
	assert.throws(() => validateOptions({ off: '' }), /written reason/);
	assert.throws(() => validateOptions({ off: '   ' }), /written reason/);
	assert.throws(() => validateOptions({ off: 42 as unknown as string }), /written reason/);
});

test('no options is a valid, armed net', () => {
	assert.deepEqual(validateOptions(undefined), {});
	assert.deepEqual(validateOptions({}), {});
});

test('an allow entry needs a reason and a non-empty match', () => {
	assert.doesNotThrow(() => validateOptions({ allow: [{ match: 'each_key_duplicate', reason: '#1234' }] }));
	assert.throws(() => validateOptions({ allow: [{ match: 'x', reason: ' ' }] }), /needs a written reason/);
	assert.throws(
		() => validateOptions({ allow: [{ match: 'x', reason: undefined as unknown as string }] }),
		/needs a written reason/
	);
	assert.throws(() => validateOptions({ allow: [{ match: '', reason: 'r' }] }), /empty match/);
	assert.throws(() => validateOptions({ allow: [{ match: new RegExp(''), reason: 'r' }] }), /empty match/);
});

test('off and allow together is refused', () => {
	assert.throws(
		() => validateOptions({ off: 'r', allow: [{ match: 'x', reason: 'r' }] }),
		/off already excuses everything/
	);
});

const crash = (text: string): Crash => ({ kind: 'pageerror', url: 'http://localhost/x', text });

test('settle keeps unexcused crashes, records the excused ones with their reason', () => {
	const out = settle(
		[crash('TypeError: a'), crash('each_key_duplicate at Chart'), crash('TypeError: b')],
		[{ match: 'each_key_duplicate', reason: '#1234' }]
	);
	assert.deepEqual(
		out.crashes.map((c) => c.text),
		['TypeError: a', 'TypeError: b']
	);
	assert.deepEqual(out.allowed, [{ crash: crash('each_key_duplicate at Chart'), reason: '#1234' }]);
	assert.deepEqual(out.stale, []);
});

test('settle reports an allow entry that excused nothing as stale', () => {
	const entry = { match: /NaN height/, reason: 'old bug' };
	const out = settle([crash('TypeError: a')], [entry]);
	assert.deepEqual(out.stale, [entry]);
	assert.equal(out.crashes.length, 1);
});

test('settle with nothing recorded and nothing allowed is clean', () => {
	assert.deepEqual(settle([]), { crashes: [], allowed: [], stale: [] });
});

test('describeCrash names the kind and page, and truncates a long stack', () => {
	assert.equal(describeCrash(crash('boom')), '[pageerror] http://localhost/x: boom');
	const long = describeCrash(crash('x'.repeat(2000)));
	assert.ok(long.length < 700);
	assert.ok(long.endsWith('…'));
});

test('githubWarning keeps a multi-line stack in one escaped annotation', () => {
	assert.equal(
		githubWarning('crash-net, report: x', 'line 1\nline 2 100%'),
		'::warning title=crash-net%2C report%3A x::line 1%0Aline 2 100%25'
	);
});
