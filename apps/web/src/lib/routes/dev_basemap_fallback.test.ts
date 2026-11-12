// Unit tests for the dev-only basemap swap glue (issue #1285), against a fake
// engine: a `Map` class whose `setStyle` records each call, so the tests can
// count swaps without WebGL.
//
// Invocation:
//   npx tsx --test src/lib/routes/dev_basemap_fallback.test.ts

import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';

import { installDevBasemapFallback } from './dev_basemap_fallback';
import { OSM_FALLBACK_STYLE_URL } from './map-style-url';
import type { Bbox } from './dev_basemap_coverage';

const VIRGINIA: Bbox = [-83.68, 36.54, -75.24, 39.47];
const RICHMOND: Bbox = [-77.5, 37.5, -77.4, 37.6];
const LONDON: Bbox = [-0.2, 51.45, -0.05, 51.55];

type Listener = () => void;

interface Call {
	style: unknown;
	transformed: boolean;
}

function fakeEngine() {
	class FakeMap {
		_interactive = true;
		bounds: Bbox;
		calls: Call[] = [];
		listeners = new Map<string, Listener[]>();
		constructor(style: string, bounds: Bbox) {
			this.bounds = bounds;
			this.setStyle(style);
		}
		setStyle(style: unknown, options?: { transformStyle?: unknown }) {
			this.calls.push({ style, transformed: !!options?.transformStyle });
			return this;
		}
		on(event: string, fn: Listener) {
			this.listeners.set(event, [...(this.listeners.get(event) ?? []), fn]);
			return this;
		}
		once(event: string, fn: Listener) {
			const wrapped = () => {
				this.listeners.set(event, (this.listeners.get(event) ?? []).filter((l) => l !== wrapped));
				fn();
			};
			return this.on(event, wrapped);
		}
		emit(event: string) {
			for (const fn of [...(this.listeners.get(event) ?? [])]) fn();
		}
		/// Runs right after the next getBounds has read the viewport.
		afterNextRead: (() => void) | null = null;
		getBounds() {
			const [w, s, e, n] = this.bounds;
			const after = this.afterNextRead;
			this.afterNextRead = null;
			after?.();
			return { getWest: () => w, getSouth: () => s, getEast: () => e, getNorth: () => n };
		}
		/// Styles this map was swapped to, in order (the constructor's own
		/// setStyle is the first call and is not a swap).
		swaps() {
			return this.calls.slice(1).map((c) => c.style);
		}
	}
	return { Map: FakeMap } as unknown as typeof import('maplibre-gl') & { Map: typeof FakeMap };
}

type FakeMapT = InstanceType<ReturnType<typeof fakeEngine>['Map']>;

/// Every test gets its own local style URL: the module caches style docs and
/// coverage per URL for the life of the process.
let seq = 0;
let localUrl = '';

function styleDocFor(url: string): unknown {
	if (url.endsWith('/data/v3.json')) return { bounds: VIRGINIA };
	if (url.endsWith(OSM_FALLBACK_STYLE_URL)) {
		return { version: 8, sources: { osm: { type: 'raster' } }, layers: [{ id: 'osm', source: 'osm' }] };
	}
	return {
		version: 8,
		sources: { protomaps: { type: 'vector', url: `${new URL(url).origin}/data/v3.json` } },
		layers: [{ id: 'earth', source: 'protomaps' }],
	};
}

const originalFetch = globalThis.fetch;
const originalLocation = (globalThis as { location?: unknown }).location;
const originalInfo = console.info;

beforeEach(() => {
	seq += 1;
	localUrl = `http://localhost:${18000 + seq}/styles/basic/style.json`;
	(globalThis as { location?: unknown }).location = { href: 'http://localhost:7777/' };
	console.info = () => {};
	globalThis.fetch = (async (input: string | URL) =>
		new Response(JSON.stringify(styleDocFor(String(input))), { status: 200 })) as typeof fetch;
});

afterEach(() => {
	globalThis.fetch = originalFetch;
	(globalThis as { location?: unknown }).location = originalLocation;
	console.info = originalInfo;
});

/// Let every pending check run to completion. Each check awaits a handful of
/// already-resolved promises and fetch responses, so a few macrotask turns
/// drain them; it does not wait on a clock.
async function settle() {
	for (let i = 0; i < 10; i++) await new Promise((r) => setImmediate(r));
}

function moveTo(map: FakeMapT, bounds: Bbox) {
	map.bounds = bounds;
	map.emit('moveend');
}

test('swaps once on leaving the extract and once on coming back, without flapping', async () => {
	const engine = fakeEngine();
	installDevBasemapFallback(engine, localUrl);
	const map = new engine.Map(localUrl, RICHMOND);
	map.emit('load');
	await settle();
	assert.deepEqual(map.swaps(), [], 'inside the extract on load: no swap');

	moveTo(map, LONDON);
	await settle();
	moveTo(map, LONDON);
	await settle();
	assert.deepEqual(map.swaps(), [OSM_FALLBACK_STYLE_URL], 'a second settle outside does not swap again');

	moveTo(map, RICHMOND);
	await settle();
	moveTo(map, RICHMOND);
	await settle();
	assert.deepEqual(map.swaps(), [OSM_FALLBACK_STYLE_URL, localUrl]);
	assert.ok(map.calls.slice(1).every((c) => c.transformed), 'every swap carries the overlays across');
});

test('installing twice wraps setStyle once and registers one listener per event', async () => {
	const engine = fakeEngine();
	installDevBasemapFallback(engine, localUrl);
	installDevBasemapFallback(engine, localUrl);
	const map = new engine.Map(localUrl, RICHMOND);
	assert.equal(map.calls.length, 1, 'the constructor setStyle reaches the engine once');
	assert.equal(map.listeners.get('moveend')?.length, 1);
	assert.equal(map.listeners.get('load')?.length, 1);

	moveTo(map, LONDON);
	await settle();
	assert.deepEqual(map.swaps(), [OSM_FALLBACK_STYLE_URL]);
});

test('a map made under an earlier install keeps one checker after a reinstall', async () => {
	const engine = fakeEngine();
	installDevBasemapFallback(engine, localUrl);
	const map = new engine.Map(localUrl, RICHMOND);
	installDevBasemapFallback(engine, localUrl);
	map.setStyle(localUrl);
	map.emit('style.load');
	await settle();
	assert.equal(map.listeners.get('moveend')?.length, 1);

	moveTo(map, LONDON);
	await settle();
	assert.deepEqual(map.swaps().filter((s) => s === OSM_FALLBACK_STYLE_URL), [OSM_FALLBACK_STYLE_URL]);
});

test('an empty style URL uninstalls a previous install', () => {
	const engine = fakeEngine();
	const pristine = engine.Map.prototype.setStyle;
	installDevBasemapFallback(engine, localUrl);
	assert.notEqual(engine.Map.prototype.setStyle, pristine);
	installDevBasemapFallback(engine, '');
	assert.equal(engine.Map.prototype.setStyle, pristine);
});

test('a settle that lands while a check runs is checked again once it finishes', async () => {
	const engine = fakeEngine();
	installDevBasemapFallback(engine, localUrl);
	const map = new engine.Map(localUrl, LONDON);
	map.emit('load');
	await settle();
	assert.deepEqual(map.swaps(), [OSM_FALLBACK_STYLE_URL]);

	// Back inside; the viewport moves out again the moment that check has read
	// it, so the settle for the move lands while the check is still running.
	map.afterNextRead = () => moveTo(map, LONDON);
	moveTo(map, RICHMOND);
	await settle();

	assert.deepEqual(
		map.swaps(),
		[OSM_FALLBACK_STYLE_URL, localUrl, OSM_FALLBACK_STYLE_URL],
		'the stale check swaps to local, and the re-check puts the fallback back for the viewport now shown',
	);
});

test('the flyover export map (non-interactive) is never swapped', async () => {
	const engine = fakeEngine();
	installDevBasemapFallback(engine, localUrl);
	const map = Object.assign(Object.create(engine.Map.prototype), {
		_interactive: false,
		bounds: LONDON,
		calls: [],
		listeners: new Map(),
	}) as FakeMapT;
	map.setStyle(localUrl);
	assert.equal(map.listeners.size, 0);
});
