// Unit tests for the dev-only basemap coverage decision (issue #1285).
//
// Invocation:
//   npx tsx --test src/lib/routes/dev_basemap_coverage.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	basemapIds,
	carryOverlays,
	devBasemapStyle,
	tileJsonBounds,
	unionBounds,
	viewportCovered,
	type Bbox,
} from './dev_basemap_coverage';

const VIRGINIA: Bbox = [-83.68, 36.54, -75.24, 39.47];
const RICHMOND: Bbox = [-77.5, 37.5, -77.4, 37.6];
const PHILADELPHIA: Bbox = [-75.25, 39.9, -75.1, 40.0];
const WORLD: Bbox = [-180, -85.0511, 180, 85.0511];

test('tileJsonBounds reads a well-formed bounds array', () => {
	assert.deepEqual(tileJsonBounds({ tilejson: '3.0.0', bounds: VIRGINIA }), VIRGINIA);
});

test('tileJsonBounds is null for missing, short, non-finite or inverted bounds', () => {
	assert.equal(tileJsonBounds(null), null);
	assert.equal(tileJsonBounds('x'), null);
	assert.equal(tileJsonBounds({}), null);
	assert.equal(tileJsonBounds({ bounds: [1, 2, 3] }), null);
	assert.equal(tileJsonBounds({ bounds: [1, 2, 3, Number.NaN] }), null);
	assert.equal(tileJsonBounds({ bounds: ['-83', '36', '-75', '39'] }), null);
	assert.equal(tileJsonBounds({ bounds: [-75, 36, -83, 39] }), null);
	assert.equal(tileJsonBounds({ bounds: [-83, 39, -75, 36] }), null);
});

test('unionBounds spans every declared box and skips unknown ones', () => {
	assert.deepEqual(unionBounds([VIRGINIA, null, PHILADELPHIA]), [-83.68, 36.54, -75.1, 40.0]);
	assert.equal(unionBounds([null, null]), null);
	assert.equal(unionBounds([]), null);
});

test('a viewport inside the extract is covered', () => {
	assert.equal(viewportCovered(VIRGINIA, RICHMOND), true);
});

test('a viewport outside the extract is not covered', () => {
	assert.equal(viewportCovered(VIRGINIA, PHILADELPHIA), false);
});

test('a viewport straddling the extract edge is not covered', () => {
	assert.equal(viewportCovered(VIRGINIA, [-76, 39, -75, 40]), false);
});

test('unknown coverage is treated as covered, so no swap happens', () => {
	assert.equal(viewportCovered(null, PHILADELPHIA), true);
});

test('a world-copied viewport is shifted back by whole turns before comparing', () => {
	assert.equal(viewportCovered(VIRGINIA, [-77.5 + 360, 37.5, -77.4 + 360, 37.6]), true);
	assert.equal(viewportCovered(VIRGINIA, [-77.5 - 720, 37.5, -77.4 - 720, 37.6]), true);
});

test('a viewport crossing the antimeridian is covered only by full-longitude coverage', () => {
	const fiji: Bbox = [178, -18, 182, -16];
	assert.equal(viewportCovered([170, -20, 180, -10], fiji), false);
	assert.equal(viewportCovered(WORLD, fiji), true);
});

test('a viewport wider than the world is covered only by full-longitude coverage', () => {
	const zoomedOut: Bbox = [-400, -60, 400, 60];
	assert.equal(viewportCovered(VIRGINIA, zoomedOut), false);
	assert.equal(viewportCovered(WORLD, zoomedOut), true);
	assert.equal(viewportCovered(WORLD, [-400, -89, 400, 89]), false);
});

test('devBasemapStyle picks the local style when covered and the fallback otherwise', () => {
	const urls = { localStyleUrl: 'http://localhost:8080/styles/basic/style.json', fallbackStyleUrl: '/osm.json' };
	assert.equal(devBasemapStyle({ coverage: VIRGINIA, viewport: RICHMOND, ...urls }), urls.localStyleUrl);
	assert.equal(devBasemapStyle({ coverage: VIRGINIA, viewport: PHILADELPHIA, ...urls }), urls.fallbackStyleUrl);
	assert.equal(devBasemapStyle({ coverage: null, viewport: PHILADELPHIA, ...urls }), urls.localStyleUrl);
});

test('carryOverlays keeps overlay sources, layers and terrain across a basemap swap', () => {
	const local = {
		version: 8,
		sources: { v3: { type: 'vector', url: 'http://localhost:8080/data/v3.json' } },
		layers: [{ id: 'background' }, { id: 'earth' }],
	};
	const previous = {
		...local,
		glyphs: 'http://localhost:8080/fonts/{fontstack}/{range}.pbf',
		sources: { ...local.sources, course: { type: 'geojson' }, dem: { type: 'raster-dem' } },
		layers: [...local.layers, { id: 'course-line' }],
		terrain: { source: 'dem', exaggeration: 1.5 },
	};
	const next: {
		version: number;
		sources: Record<string, unknown>;
		layers: { id: string }[];
		glyphs?: string;
		terrain?: unknown;
	} = {
		version: 8,
		sources: { osm: { type: 'raster' } },
		layers: [{ id: 'background' }, { id: 'osm' }],
	};
	const out = carryOverlays(previous, next, basemapIds(local));
	assert.deepEqual(Object.keys(out.sources), ['osm', 'course', 'dem']);
	assert.deepEqual(out.layers.map((l) => l.id), ['background', 'osm', 'course-line']);
	assert.deepEqual(out.terrain, { source: 'dem', exaggeration: 1.5 });
	assert.equal(out.glyphs, previous.glyphs);
});

test('carryOverlays prefers the glyphs and sprite the next style declares', () => {
	const out = carryOverlays(
		{ glyphs: 'old', sprite: 'old-sprite', sources: {}, layers: [] },
		{ glyphs: 'new', sprite: 'new-sprite', sources: {}, layers: [] },
		basemapIds({}),
	);
	assert.equal(out.glyphs, 'new');
	assert.equal(out.sprite, 'new-sprite');
});
