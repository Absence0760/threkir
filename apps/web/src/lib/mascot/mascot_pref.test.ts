import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import type { LoadedSettings } from '#lib/settings/settings_overlay.ts';
import { loadMascotShownFrom, peekMascotShownFrom, type MascotPrefSource } from './mascot_pref_read.ts';

const EMPTY: LoadedSettings = { universal: {}, device: {} };
const bag = (universal: Record<string, unknown>, device: Record<string, unknown> = {}): LoadedSettings =>
	({ universal, device }) as LoadedSettings;

function source(over: Partial<MascotPrefSource> = {}): MascotPrefSource {
	return {
		userId: 'u1',
		peek: () => EMPTY,
		load: async () => EMPTY,
		...over,
	};
}

const blocked = (): never => {
	throw new DOMException('The operation is insecure.', 'SecurityError');
};

// The warnings are the point of the failure paths, but not of the test output.
function quietly<T>(fn: () => T): T {
	const warn = console.warn;
	console.warn = () => {};
	try {
		return fn();
	} finally {
		console.warn = warn;
	}
}
async function quietlyAsync<T>(fn: () => Promise<T>): Promise<T> {
	const warn = console.warn;
	console.warn = () => {};
	try {
		return await fn();
	} finally {
		console.warn = warn;
	}
}

test('peek: signed out is unknown, and the cache is not read', () => {
	let reads = 0;
	const peek = () => {
		reads++;
		return bag({ show_mascot: true });
	};
	assert.equal(peekMascotShownFrom(source({ userId: null, peek })), null);
	assert.equal(peekMascotShownFrom(source({ userId: undefined, peek })), null);
	assert.equal(peekMascotShownFrom(source({ userId: '', peek })), null);
	assert.equal(reads, 0);
});

test('peek: a cold cache is unknown, not on', () => {
	assert.equal(peekMascotShownFrom(source()), null);
});

test('peek: a stored true or false reads back as stored', () => {
	assert.equal(peekMascotShownFrom(source({ peek: () => bag({ show_mascot: true }) })), true);
	assert.equal(peekMascotShownFrom(source({ peek: () => bag({ show_mascot: false }) })), false);
	assert.equal(peekMascotShownFrom(source({ peek: () => bag({}, { show_mascot: false }) })), false);
});

test('peek: a warm cache without the key is the default, on', () => {
	assert.equal(peekMascotShownFrom(source({ peek: () => bag({ preferred_unit: 'km' }) })), true);
});

test('peek: the device bag overrides the universal one', () => {
	assert.equal(
		peekMascotShownFrom(source({ peek: () => bag({ show_mascot: true }, { show_mascot: false }) })),
		false,
	);
});

test('peek: the cache is read for the signed-in runner', () => {
	const seen: string[] = [];
	peekMascotShownFrom(source({ userId: 'runner-7', peek: (uid) => (seen.push(uid), EMPTY) }));
	assert.deepEqual(seen, ['runner-7']);
});

test('peek: storage that throws (a private window) is unknown, not a crash', () => {
	assert.equal(quietly(() => peekMascotShownFrom(source({ peek: blocked }))), null);
});

test('load: signed out is unknown, and nothing is fetched', async () => {
	let fetches = 0;
	const load = async () => {
		fetches++;
		return bag({ show_mascot: true });
	};
	assert.equal(await loadMascotShownFrom(source({ userId: null, load })), null);
	assert.equal(fetches, 0);
});

test('load: the server answer wins over the cache', async () => {
	const src = source({ peek: () => bag({ show_mascot: true }), load: async () => bag({ show_mascot: false }) });
	assert.equal(await loadMascotShownFrom(src), false);
	assert.equal(
		await loadMascotShownFrom(source({ load: async () => bag({ show_mascot: true }) })),
		true,
	);
});

test('load: an empty server bag is the default, on', async () => {
	// Unlike a cold cache, the server has answered: nobody hid him.
	assert.equal(await loadMascotShownFrom(source()), true);
});

test('load: a failed read falls back to the cached answer', async () => {
	const failing = async (): Promise<LoadedSettings> => {
		throw new Error('offline');
	};
	assert.equal(
		await quietlyAsync(() => loadMascotShownFrom(source({ load: failing, peek: () => bag({ show_mascot: false }) }))),
		false,
	);
	assert.equal(await quietlyAsync(() => loadMascotShownFrom(source({ load: failing }))), null);
});

test('load: a server read that failed on a cold cache is unknown, not on', async () => {
	// loadSettings resolves here instead of throwing, with empty bags and
	// universalUnknown set; reading those as "nobody hid him" showed him.
	const coldOffline = async (): Promise<LoadedSettings> => ({ universal: {}, device: {}, universalUnknown: true });
	assert.equal(await loadMascotShownFrom(source({ load: coldOffline })), null);
	// A device-bag value is still the runner's own answer.
	const deviceOff = async (): Promise<LoadedSettings> => ({ universal: {}, device: { show_mascot: false }, universalUnknown: true });
	assert.equal(await loadMascotShownFrom(source({ load: deviceOff })), false);
});

test('load: a failed read with blocked storage resolves unknown, never rejects', async () => {
	assert.equal(await quietlyAsync(() => loadMascotShownFrom(source({ load: async () => blocked(), peek: blocked }))), null);
});

test('peek and load agree on the same stored value', async () => {
	for (const stored of [bag({ show_mascot: true }), bag({ show_mascot: false }), bag({}, { show_mascot: false }), bag({ unit: 'mi' })]) {
		const src = source({ peek: () => stored, load: async () => stored });
		assert.equal(peekMascotShownFrom(src), await loadMascotShownFrom(src), JSON.stringify(stored));
	}
});

test('mascot_pref wires the signed-in user and the real settings cache', () => {
	const src = readFileSync(resolve(import.meta.dirname, 'mascot_pref.ts'), 'utf8');
	assert.match(src, /userId: auth\.user\?\.id, peek: peekCachedSettings, load: loadSettings/);
});
