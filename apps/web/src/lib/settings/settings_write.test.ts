import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	SettingsWriteError,
	classifyWriteFailure,
	drainQueue,
	failureOf,
	pushOrQueue,
	pushWithoutRefusedHealthPrefs,
	withoutHealthConsentPrefs,
} from './settings_write';

// postgrest-js's fetch catch: no code, status 0, the message prefixed
// with the thrown error's name.
const OFFLINE = {
	error: { message: 'TypeError: Failed to fetch', code: '' },
	status: 0,
};
const RLS_DENIED = {
	error: {
		message: 'new row violates row-level security policy for table "user_settings"',
		code: '42501',
	},
	status: 403,
};
const CHECK_VIOLATION = {
	error: { message: 'new row for relation "user_settings" violates check constraint', code: '23514' },
	status: 400,
};

test('a fetch failure is a transport failure', () => {
	assert.equal(classifyWriteFailure(OFFLINE), 'transport');
	assert.equal(
		classifyWriteFailure({ error: { message: 'FetchError: network timeout' }, status: 0 }),
		'transport',
	);
});

test('a proxy that answered with an unparseable body is still the server rejecting', () => {
	assert.equal(
		classifyWriteFailure({ error: { message: '<html>502 Bad Gateway</html>' }, status: 502 }),
		'rejected',
	);
});

test('every structured PostgREST refusal is a rejection', () => {
	assert.equal(classifyWriteFailure(RLS_DENIED), 'rejected');
	assert.equal(classifyWriteFailure(CHECK_VIOLATION), 'rejected');
	assert.equal(
		classifyWriteFailure({ error: { message: 'JWT expired', code: 'PGRST301' }, status: 401 }),
		'rejected',
	);
});

test('SettingsWriteError carries the server message and its classification', () => {
	const err = new SettingsWriteError(RLS_DENIED);
	assert.equal(err.failure, 'rejected');
	assert.equal(err.code, '42501');
	assert.match(err.message, /row-level security/);
	assert.ok(err instanceof Error);
});

test('an unclassified throw is treated as a rejection, not as being offline', () => {
	assert.equal(failureOf(new Error('boom')), 'rejected');
	assert.equal(failureOf(undefined), 'rejected');
	assert.equal(failureOf(new SettingsWriteError(OFFLINE)), 'transport');
});

test('a transport failure queues the change and resolves', async () => {
	let queued = 0;
	let rolledBack = 0;
	await pushOrQueue({
		push: () => Promise.reject(new SettingsWriteError(OFFLINE)),
		queue: () => (queued += 1),
		rollback: () => (rolledBack += 1),
	});
	assert.equal(queued, 1);
	assert.equal(rolledBack, 0);
});

test('a rejected write rolls back the optimistic cache write, never queues, and rethrows', async () => {
	let queued = 0;
	let rolledBack = 0;
	await assert.rejects(
		pushOrQueue({
			push: () => Promise.reject(new SettingsWriteError(RLS_DENIED)),
			queue: () => (queued += 1),
			rollback: () => (rolledBack += 1),
		}),
		/row-level security/,
	);
	assert.equal(queued, 0, 'a doomed write must not enter the pending queue');
	assert.equal(rolledBack, 1, 'the local bag must not keep a value the server refused');
});

test('a successful write neither queues nor rolls back', async () => {
	let queued = 0;
	let rolledBack = 0;
	await pushOrQueue({
		push: () => Promise.resolve(),
		queue: () => (queued += 1),
		rollback: () => (rolledBack += 1),
	});
	assert.equal(queued, 0);
	assert.equal(rolledBack, 0);
});

test('draining a queue that all lands clears it', async () => {
	const sent: string[] = [];
	const unsent = await drainQueue(['a', 'b', 'c'], async (c) => {
		sent.push(c);
	});
	assert.deepEqual(sent, ['a', 'b', 'c']);
	assert.deepEqual(unsent, []);
});

test('a transport failure mid-drain keeps that entry and everything after it, in order', async () => {
	const sent: string[] = [];
	const unsent = await drainQueue(['a', 'b', 'c'], async (c) => {
		if (c === 'b') throw new SettingsWriteError(OFFLINE);
		sent.push(c);
	});
	assert.deepEqual(sent, ['a']);
	assert.deepEqual(unsent, ['b', 'c']);
});

test('a rejected entry is dropped so it cannot block the queue behind it forever', async () => {
	const sent: string[] = [];
	const unsent = await drainQueue(['a', 'b', 'c'], async (c) => {
		if (c === 'b') throw new SettingsWriteError(RLS_DENIED);
		sent.push(c);
	});
	assert.deepEqual(sent, ['a', 'c']);
	assert.deepEqual(unsent, []);
});

// Decisions § 2542: a weight queued offline can replay after consent was
// withdrawn on another device, and the database refuses it (42501).
test('a queued change refused for want of consent lands again without its gated values', async () => {
	const pushed: Record<string, unknown>[] = [];
	await pushWithoutRefusedHealthPrefs({ body_weight_kg: 81.5, weight_unit: 'kg' }, async (c) => {
		pushed.push(c);
		if ('body_weight_kg' in c) throw new SettingsWriteError(RLS_DENIED);
	});
	assert.deepEqual(pushed, [{ body_weight_kg: 81.5, weight_unit: 'kg' }, { weight_unit: 'kg' }]);
});

test('the consent retry drains through, so the change behind it is not blocked', async () => {
	const sent: Record<string, unknown>[] = [];
	const push = async (c: Record<string, unknown>) => {
		if (c.body_weight_kg != null) throw new SettingsWriteError(RLS_DENIED);
		sent.push(c);
	};
	const unsent = await drainQueue(
		[{ body_weight_kg: 81.5 }, { locale: 'de' }],
		(c) => pushWithoutRefusedHealthPrefs(c, push),
	);
	assert.deepEqual(sent, [{}, { locale: 'de' }]);
	assert.deepEqual(unsent, []);
});

test('a 42501 with no gated value to remove is rethrown, not retried', async () => {
	let calls = 0;
	await assert.rejects(
		pushWithoutRefusedHealthPrefs({ privacy_default: 'public' }, async () => {
			calls++;
			throw new SettingsWriteError(RLS_DENIED);
		}),
		SettingsWriteError,
	);
	assert.equal(calls, 1);
});

test('a refusal other than 42501, or a transport failure, is not retried without the gated values', async () => {
	for (const failure of [CHECK_VIOLATION, OFFLINE]) {
		let calls = 0;
		await assert.rejects(
			pushWithoutRefusedHealthPrefs({ body_weight_kg: 81.5 }, async () => {
				calls++;
				throw new SettingsWriteError(failure);
			}),
		);
		assert.equal(calls, 1);
	}
});

test('a gated key set to null is kept: removing a value is never refused', () => {
	assert.equal(withoutHealthConsentPrefs({ body_weight_kg: null, locale: 'de' }), null);
	assert.deepEqual(withoutHealthConsentPrefs({ body_weight_kg: 70, hr_medication_affected: null }), {
		hr_medication_affected: null,
	});
});
