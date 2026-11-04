// Invocation:
//   npx tsx --test src/lib/routes/terrain_source.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	AWS_TERRAIN_SOURCE,
	AWS_TERRAIN_TILES_HOST,
	FLYOVER_PITCH,
	LOW_RELIEF_M,
	MAX_TERRAIN_EXAGGERATION,
	resolveTerrainSource,
	TERRAIN_EXAGGERATION,
	terrainExaggeration,
} from './terrain_source';

test('no key and no override falls back to the keyless AWS terrarium tiles', () => {
	const src = resolveTerrainSource({ maptilerKey: '', override: '' });
	assert.deepEqual(src, AWS_TERRAIN_SOURCE);
	assert.equal(src.encoding, 'terrarium');
	assert.equal(src.tileSize, 256);
	assert.equal(src.maxzoom, 15);
	assert.deepEqual(src.tiles, [
		'https://elevation-tiles-prod.s3.amazonaws.com/terrarium/{z}/{x}/{y}.png',
	]);
});

test('the AWS tiles are requested from the one bucket host the CSP allows', () => {
	for (const t of AWS_TERRAIN_SOURCE.tiles) {
		assert.equal(new URL(t.replace(/\{(\w)\}/g, '0')).host, AWS_TERRAIN_TILES_HOST);
	}
});

test('the AWS source links its upstream data attribution', () => {
	assert.match(AWS_TERRAIN_SOURCE.attribution, /tilezen\/joerd\/blob\/master\/docs\/attribution\.md/);
	assert.match(AWS_TERRAIN_SOURCE.attribution, /Mapzen/);
	assert.match(AWS_TERRAIN_SOURCE.attribution, /USGS/);
});

test('a MapTiler key selects terrain-rgb-v2 in the Mapbox encoding at 512 px', () => {
	const src = resolveTerrainSource({ maptilerKey: 'KEY', override: '' });
	assert.deepEqual(src.tiles, ['https://api.maptiler.com/tiles/terrain-rgb-v2/{z}/{x}/{y}?key=KEY']);
	assert.equal(src.encoding, 'mapbox');
	assert.equal(src.tileSize, 512);
	assert.equal(src.maxzoom, 14);
	assert.match(src.attribution, /MapTiler/);
	assert.match(src.attribution, /OpenStreetMap/);
});

test('the key is URL-encoded into the template', () => {
	const src = resolveTerrainSource({ maptilerKey: 'a&b', override: '' });
	assert.ok(src.tiles[0].endsWith('?key=a%26b'));
});

test('a whitespace-only key is treated as absent', () => {
	assert.deepEqual(resolveTerrainSource({ maptilerKey: '   ', override: '' }), AWS_TERRAIN_SOURCE);
});

test('the override wins over a MapTiler key', () => {
	const src = resolveTerrainSource({
		maptilerKey: 'KEY',
		override: 'http://localhost:8080/data/terrain/{z}/{x}/{y}.webp',
	});
	assert.deepEqual(src.tiles, ['http://localhost:8080/data/terrain/{z}/{x}/{y}.webp']);
	assert.equal(src.encoding, 'mapbox');
	assert.equal(src.tileSize, 512);
	assert.equal(src.attribution, '');
});

test('an override naming terrarium is read as terrarium-encoded 256 px tiles', () => {
	const src = resolveTerrainSource({
		maptilerKey: '',
		override: '  http://localhost:8080/data/Terrarium/{z}/{x}/{y}.png  ',
	});
	assert.deepEqual(src.tiles, ['http://localhost:8080/data/Terrarium/{z}/{x}/{y}.png']);
	assert.equal(src.encoding, 'terrarium');
	assert.equal(src.tileSize, 256);
	assert.equal(src.maxzoom, 15);
});

test('a whitespace-only override is treated as absent', () => {
	const src = resolveTerrainSource({ maptilerKey: 'KEY', override: '   ' });
	assert.equal(src.encoding, 'mapbox');
	assert.ok(src.tiles[0].startsWith('https://api.maptiler.com/'));
});

test('the view constants match the product decision', () => {
	assert.equal(TERRAIN_EXAGGERATION, 1.5);
	assert.equal(FLYOVER_PITCH, 60);
});

test('a course with 100 m of relief or more keeps the base exaggeration, mountains included', () => {
	assert.equal(LOW_RELIEF_M, 100);
	assert.equal(terrainExaggeration(100), TERRAIN_EXAGGERATION);
	assert.equal(terrainExaggeration(450), TERRAIN_EXAGGERATION);
	assert.equal(terrainExaggeration(2500), TERRAIN_EXAGGERATION);
});

test('a low-relief course is exaggerated in inverse proportion, up to the bound', () => {
	assert.equal(terrainExaggeration(75), 2);
	assert.equal(MAX_TERRAIN_EXAGGERATION, 3);
	assert.equal(terrainExaggeration(50), 3);
	// Philadelphia's chart: 6 m by the river to 50 m above the Schuylkill.
	assert.equal(terrainExaggeration(44), 3);
	assert.equal(terrainExaggeration(5), 3);
	assert.equal(terrainExaggeration(0.001), 3);
});

test('an unknown or degenerate relief keeps the base exaggeration', () => {
	for (const r of [null, 0, -10, Number.NaN, Number.POSITIVE_INFINITY]) {
		assert.equal(terrainExaggeration(r), TERRAIN_EXAGGERATION, String(r));
	}
});
