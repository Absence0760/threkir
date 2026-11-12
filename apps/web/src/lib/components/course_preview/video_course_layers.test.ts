import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { buildFlyoverPath, type PathPoint } from '#lib/routes/flyover_path.ts';
import { stripComments } from '#lib/core/strip_comments.ts';
import type maplibregl from '#lib/routes/maplibre.ts';
import { addCourseLayers, START_FINISH_LAYER_IDS } from './course_layers.ts';
import { videoCourseLayerInput } from './video_course_layers.ts';

const LABELS = { start: 'Start', finish: 'Finish', startFinish: 'Start / Finish' };

function pts(coords: [number, number][]): PathPoint[] {
	return coords.map(([lat, lng]) => ({ lat, lng, ele: null }));
}

/// Records what `addCourseLayers` asks of the map.
function fakeMap() {
	const sources = new Map<string, { data: { features: { properties: Record<string, unknown> }[] } }>();
	const layers: { id: string; source: string; layout?: Record<string, unknown> }[] = [];
	const images = new Map<string, unknown>();
	const map = {
		addSource: (id: string, spec: never) => void sources.set(id, spec),
		addLayer: (spec: never) => void layers.push(spec),
		addImage: (id: string, img: unknown) => void images.set(id, img),
		hasImage: (id: string) => images.has(id),
	};
	return { map: map as unknown as maplibregl.Map, sources, layers, images };
}

const twoKm = buildFlyoverPath(pts([[51.5, -0.1], [51.51, -0.1], [51.52, -0.1]]));

test('the export draws the start / finish layers above the km markers', () => {
	const f = fakeMap();
	addCourseLayers(f.map, videoCourseLayerInput({ path: twoKm, unit: 'km', climbs: [], text: { startFinish: LABELS } }, true));
	const ids = f.layers.map((l) => l.id);
	for (const id of ['course-line', 'course-marker-bg', 'course-marker-text', ...START_FINISH_LAYER_IDS]) {
		assert.ok(ids.includes(id), `missing ${id}`);
	}
	assert.ok(ids.indexOf(START_FINISH_LAYER_IDS[0]) > ids.indexOf('course-marker-text'));
	const features = f.sources.get('course-start-finish')!.data.features;
	assert.deepEqual(
		features.map((ft) => ft.properties.label),
		['Start', 'Finish'],
	);
	// Every icon a feature names is registered.
	for (const ft of features) assert.ok(f.images.has(ft.properties.icon as string));
	assert.equal(f.images.size, 2);
});

test('a loop export draws one Start / Finish marker', () => {
	const loop = buildFlyoverPath(pts([[51.5, -0.1], [51.51, -0.1], [51.51, -0.09], [51.5, -0.1]]));
	const input = videoCourseLayerInput({ path: loop, unit: 'km', climbs: [], text: { startFinish: LABELS } }, false);
	assert.deepEqual(
		input.startFinish.map((s) => s.label),
		['Start / Finish'],
	);
	const f = fakeMap();
	addCourseLayers(f.map, input);
	assert.equal(f.sources.get('course-start-finish')!.data.features.length, 1);
	assert.equal(f.images.size, 1);
});

test('renderFlyoverVideo builds its map layers through videoCourseLayerInput', () => {
	const src = stripComments(readFileSync(resolve(import.meta.dirname, 'flyover_video_export.ts'), 'utf8'));
	assert.match(src, /addCourseLayers\(\s*m,\s*videoCourseLayerInput\(input,\s*darkBasemap\)\s*\)/);
});
