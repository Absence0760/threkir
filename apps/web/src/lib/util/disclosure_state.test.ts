import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	disclosureStorageKey,
	mergeDisclosureState,
	readDisclosureState,
	writeDisclosureState,
	type DisclosureState,
} from './disclosure_state';

const DEFAULTS: DisclosureState = { progress: true, calendar: false, weeks: true };

/// Minimal Storage stand-in. `throwOn` makes the two failure modes the
/// helpers must survive reproducible: a private window that refuses the read,
/// and a quota-exhausted write.
function fakeStorage(opts: { throwOn?: 'get' | 'set' } = {}) {
	const map = new Map<string, string>();
	return {
		map,
		getItem(key: string): string | null {
			if (opts.throwOn === 'get') throw new DOMException('denied', 'SecurityError');
			return map.get(key) ?? null;
		},
		setItem(key: string, value: string): void {
			if (opts.throwOn === 'set') throw new DOMException('quota', 'QuotaExceededError');
			map.set(key, value);
		},
	};
}

function withStorage<T>(storage: unknown, fn: () => T): T {
	const g = globalThis as { localStorage?: unknown };
	const had = 'localStorage' in g;
	const previous = g.localStorage;
	g.localStorage = storage;
	try {
		return fn();
	} finally {
		if (had) g.localStorage = previous;
		else delete g.localStorage;
	}
}

test('the storage key is scoped to both the surface and the account', () => {
	assert.equal(disclosureStorageKey('plan_detail', 'u-1'), 'run_app.disclosure_v1:plan_detail:u-1');
	assert.notEqual(
		disclosureStorageKey('plan_detail', 'u-1'),
		disclosureStorageKey('plan_detail', 'u-2'),
	);
	assert.notEqual(
		disclosureStorageKey('plan_detail', 'u-1'),
		disclosureStorageKey('run_detail', 'u-1'),
	);
});

test('a signed-out viewer gets a key of its own rather than the last account key', () => {
	assert.equal(disclosureStorageKey('plan_detail', null), 'run_app.disclosure_v1:plan_detail:anon');
	assert.equal(
		disclosureStorageKey('plan_detail', undefined),
		'run_app.disclosure_v1:plan_detail:anon',
	);
});

test('merging keeps the defaults for anything the blob does not carry', () => {
	assert.deepEqual(mergeDisclosureState(DEFAULTS, { calendar: true }), {
		progress: true,
		calendar: true,
		weeks: true,
	});
});

test('merging drops a key the surface no longer declares', () => {
	const merged = mergeDisclosureState(DEFAULTS, { calendar: true, retired: false });
	assert.deepEqual(Object.keys(merged).sort(), ['calendar', 'progress', 'weeks']);
});

test('merging ignores a non-boolean value rather than coercing it', () => {
	assert.deepEqual(mergeDisclosureState(DEFAULTS, { progress: 'no', weeks: 0, calendar: true }), {
		progress: true,
		calendar: true,
		weeks: true,
	});
});

test('merging a blob that is not an object falls back to the defaults', () => {
	for (const stored of [null, undefined, 42, 'open', ['weeks'], true]) {
		assert.deepEqual(mergeDisclosureState(DEFAULTS, stored), DEFAULTS, `stored=${String(stored)}`);
	}
});

test('merging never mutates the defaults it was handed', () => {
	const defaults = { ...DEFAULTS };
	mergeDisclosureState(defaults, { calendar: true });
	assert.deepEqual(defaults, DEFAULTS);
});

test('a written state reads back for the same account', () => {
	const storage = fakeStorage();
	withStorage(storage, () => {
		writeDisclosureState('plan_detail', 'u-1', { ...DEFAULTS, calendar: true });
		assert.deepEqual(readDisclosureState('plan_detail', 'u-1', DEFAULTS), {
			progress: true,
			calendar: true,
			weeks: true,
		});
	});
});

test('one account does not read another account state on a shared browser', () => {
	const storage = fakeStorage();
	withStorage(storage, () => {
		writeDisclosureState('plan_detail', 'u-1', { ...DEFAULTS, weeks: false });
		assert.deepEqual(readDisclosureState('plan_detail', 'u-2', DEFAULTS), DEFAULTS);
	});
});

test('a cold read with nothing stored returns the defaults', () => {
	withStorage(fakeStorage(), () => {
		assert.deepEqual(readDisclosureState('plan_detail', 'u-1', DEFAULTS), DEFAULTS);
	});
});

test('a corrupt blob returns the defaults instead of throwing', () => {
	const storage = fakeStorage();
	storage.map.set(disclosureStorageKey('plan_detail', 'u-1'), '{not json');
	withStorage(storage, () => {
		assert.deepEqual(readDisclosureState('plan_detail', 'u-1', DEFAULTS), DEFAULTS);
	});
});

test('a storage that refuses the read returns the defaults', () => {
	withStorage(fakeStorage({ throwOn: 'get' }), () => {
		assert.deepEqual(readDisclosureState('plan_detail', 'u-1', DEFAULTS), DEFAULTS);
	});
});

test('a storage that refuses the write does not throw at the call site', () => {
	withStorage(fakeStorage({ throwOn: 'set' }), () => {
		assert.doesNotThrow(() => writeDisclosureState('plan_detail', 'u-1', DEFAULTS));
	});
});

test('no storage at all (SSR) reads defaults and writes silently', () => {
	const g = globalThis as { localStorage?: unknown };
	const had = 'localStorage' in g;
	const previous = g.localStorage;
	delete g.localStorage;
	try {
		assert.deepEqual(readDisclosureState('plan_detail', 'u-1', DEFAULTS), DEFAULTS);
		assert.doesNotThrow(() => writeDisclosureState('plan_detail', 'u-1', DEFAULTS));
	} finally {
		if (had) g.localStorage = previous;
	}
});
