import { test } from 'node:test';
import assert from 'node:assert/strict';

import { AWS_TERRAIN_SOURCE } from '#lib/routes/terrain_source.ts';
import {
	addCourseTerrain,
	HILLSHADE_LAYER_ID,
	HILLSHADE_SOURCE_ID,
	hillshadeBeforeId,
	removeCourseTerrain,
	styleHasHillshade,
	TERRAIN_SOURCE_ID,
	type TerrainTarget,
} from './course_terrain.ts';

type Call = [string, ...unknown[]];

function fakeMap(
	layers: { id: string; type: string }[],
	fail: { addSource?: string; addLayer?: boolean; setTerrain?: boolean } = {},
) {
	const calls: Call[] = [];
	const present = new Set<string>();
	const target: TerrainTarget = {
		addSource(id, source) {
			if (fail.addSource === id) throw new Error(`no ${id}`);
			calls.push(['addSource', id, source]);
		},
		addLayer(layer, beforeId) {
			if (fail.addLayer) throw new Error('no layer');
			present.add(layer.id);
			calls.push(['addLayer', layer, beforeId]);
		},
		setTerrain(t) {
			if (fail.setTerrain) throw new Error('no terrain');
			calls.push(['setTerrain', t]);
		},
		getStyle: () => ({ layers }),
		getLayer: (id) => (present.has(id) ? {} : undefined),
		removeLayer(id) {
			present.delete(id);
			calls.push(['removeLayer', id]);
		},
	};
	return { target, calls };
}

const STYLE = [
	{ id: 'background', type: 'background' },
	{ id: 'water', type: 'fill' },
	{ id: 'roads', type: 'line' },
	{ id: 'place-labels', type: 'symbol' },
	{ id: 'poi-labels', type: 'symbol' },
];

test('the hillshade goes under the first label layer, or on top of a style with none', () => {
	assert.equal(hillshadeBeforeId(STYLE), 'place-labels');
	assert.equal(hillshadeBeforeId([{ id: 'osm', type: 'raster' }]), undefined);
	assert.equal(hillshadeBeforeId(undefined), undefined);
});

test('a style that already shades relief is detected', () => {
	assert.equal(styleHasHillshade(STYLE), false);
	assert.equal(styleHasHillshade([...STYLE, { id: 'hs', type: 'hillshade' }]), true);
});

test('terrain and a hillshade from the same tiles, the hillshade under the labels', () => {
	const { target, calls } = fakeMap(STYLE);
	addCourseTerrain(target, AWS_TERRAIN_SOURCE, { exaggeration: 2.5, darkBasemap: false });
	assert.deepEqual(calls[0], ['addSource', TERRAIN_SOURCE_ID, { type: 'raster-dem', ...AWS_TERRAIN_SOURCE }]);
	assert.deepEqual(calls[1], ['setTerrain', { source: TERRAIN_SOURCE_ID, exaggeration: 2.5 }]);
	assert.deepEqual(calls[2], ['addSource', HILLSHADE_SOURCE_ID, { type: 'raster-dem', ...AWS_TERRAIN_SOURCE }]);
	const [kind, layer, beforeId] = calls[3] as [string, { id: string; type: string; source: string }, string];
	assert.equal(kind, 'addLayer');
	assert.equal(layer.id, HILLSHADE_LAYER_ID);
	assert.equal(layer.type, 'hillshade');
	assert.equal(layer.source, HILLSHADE_SOURCE_ID);
	assert.equal(beforeId, 'place-labels');
});

test('the hillshade carries the terrain source attribution, so the credit stays the source own', () => {
	const { target, calls } = fakeMap(STYLE);
	addCourseTerrain(target, AWS_TERRAIN_SOURCE, { exaggeration: 1.5, darkBasemap: true });
	const hillshade = calls.find((c) => c[0] === 'addSource' && c[1] === HILLSHADE_SOURCE_ID);
	assert.equal((hillshade?.[2] as { attribution: string }).attribution, AWS_TERRAIN_SOURCE.attribution);
});

test('a style with its own hillshade gets terrain only', () => {
	const { target, calls } = fakeMap([...STYLE, { id: 'hs', type: 'hillshade' }]);
	addCourseTerrain(target, AWS_TERRAIN_SOURCE, { exaggeration: 1.5, darkBasemap: false });
	assert.deepEqual(
		calls.map((c) => c[0]),
		['addSource', 'setTerrain'],
	);
});

test('a hillshade that fails leaves the terrain on and does not throw', () => {
	const { target, calls } = fakeMap(STYLE, { addLayer: true });
	addCourseTerrain(target, AWS_TERRAIN_SOURCE, { exaggeration: 1.5, darkBasemap: false });
	assert.ok(calls.some((c) => c[0] === 'setTerrain'));
	const { target: t2 } = fakeMap(STYLE, { addSource: HILLSHADE_SOURCE_ID });
	assert.doesNotThrow(() => addCourseTerrain(t2, AWS_TERRAIN_SOURCE, { exaggeration: 1.5, darkBasemap: false }));
});

test('a terrain that cannot be set throws for the caller to fall back, before any hillshade', () => {
	const { target, calls } = fakeMap(STYLE, { setTerrain: true });
	assert.throws(() => addCourseTerrain(target, AWS_TERRAIN_SOURCE, { exaggeration: 1.5, darkBasemap: false }));
	assert.ok(!calls.some((c) => c[1] === HILLSHADE_SOURCE_ID));
});

test('removing takes the hillshade off even when clearing the terrain throws', () => {
	const { target, calls } = fakeMap(STYLE);
	addCourseTerrain(target, AWS_TERRAIN_SOURCE, { exaggeration: 1.5, darkBasemap: false });
	target.setTerrain = () => {
		throw new Error('gone');
	};
	removeCourseTerrain(target);
	assert.deepEqual(calls.at(-1), ['removeLayer', HILLSHADE_LAYER_ID]);
	assert.doesNotThrow(() => removeCourseTerrain(target));
});
