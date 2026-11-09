import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { buildFlyoverPath, type PathPoint } from '#lib/routes/flyover_path.ts';
import { mapFinishColour, mapStartColour } from '#lib/routes/basemap_contrast.ts';
import {
	isLoopCourse,
	LOOP_CLOSE_M,
	startFinishFill,
	startFinishImageId,
	startFinishMarkers,
	startFinishPillImage,
} from './start_finish.ts';

const LABELS = { start: 'Start', finish: 'Finish', startFinish: 'Start / Finish' };
// ~111 m per 0.001 degree of latitude.
const DEG_PER_M = 1 / 111_195;

function pts(coords: [number, number][]): PathPoint[] {
	return coords.map(([lat, lng]) => ({ lat, lng, ele: null }));
}

const pointToPoint = buildFlyoverPath(pts([[51.5, -0.1], [51.51, -0.1], [51.52, -0.09]]));
const loop = buildFlyoverPath(pts([[51.5, -0.1], [51.51, -0.1], [51.51, -0.09], [51.5, -0.09], [51.5, -0.1]]));
const outAndBack = buildFlyoverPath(pts([[51.5, -0.1], [51.51, -0.1], [51.52, -0.1], [51.51, -0.1], [51.5, -0.1]]));

test('a point-to-point course gets a Start and a Finish at its two ends', () => {
	assert.equal(isLoopCourse(pointToPoint), false);
	const got = startFinishMarkers(pointToPoint, LABELS);
	assert.deepEqual(
		got.map((m) => [m.kind, m.label, m.lat, m.lng]),
		[
			['start', 'Start', 51.5, -0.1],
			['finish', 'Finish', 51.52, -0.09],
		],
	);
});

test('a loop gets one Start / Finish marker at the start', () => {
	assert.equal(isLoopCourse(loop), true);
	const got = startFinishMarkers(loop, LABELS);
	assert.deepEqual(got, [{ kind: 'startFinish', label: 'Start / Finish', lat: 51.5, lng: -0.1 }]);
});

test('an out-and-back counts as a loop by distance', () => {
	assert.equal(isLoopCourse(outAndBack), true);
	assert.deepEqual(
		startFinishMarkers(outAndBack, LABELS).map((m) => m.kind),
		['startFinish'],
	);
});

test('the loop threshold is 50 m between the first and last points', () => {
	assert.equal(LOOP_CLOSE_M, 50);
	const end = (gapM: number) =>
		buildFlyoverPath(pts([[51.5, -0.1], [51.51, -0.1], [51.5 + gapM * DEG_PER_M, -0.1]]));
	assert.equal(isLoopCourse(end(45)), true);
	assert.equal(isLoopCourse(end(55)), false);
});

test('a path with no length gets no markers', () => {
	assert.deepEqual(startFinishMarkers(buildFlyoverPath(pts([[51.5, -0.1]])), LABELS), []);
	assert.deepEqual(startFinishMarkers(buildFlyoverPath([]), LABELS), []);
});

test('the pills take the app start and finish colours, keyed by basemap', () => {
	for (const dark of [false, true]) {
		assert.equal(startFinishFill('start', dark), mapStartColour(dark));
		assert.equal(startFinishFill('startFinish', dark), mapStartColour(dark));
		assert.equal(startFinishFill('finish', dark), mapFinishColour(dark));
	}
	assert.notEqual(startFinishImageId('finish', true), startFinishImageId('finish', false));
});

test('the pill image stretches only inside its straight middle, and its content box holds the stretch', () => {
	for (const kind of ['start', 'finish', 'startFinish'] as const) {
		const img = startFinishPillImage(kind, false, 3);
		assert.equal(img.data.length, img.width * img.height * 4);
		const [[x0, x1]] = img.stretchX;
		const r = img.height / 2;
		assert.ok(x0 >= r - 1 && x1 <= img.width - r + 1, `${kind}: stretch ${x0}-${x1} in the caps`);
		const [cx0, cy0, cx1, cy1] = img.content;
		assert.ok(cx0 <= x0 && cx1 >= x1 && cy0 > 0 && cy1 < img.height);
		// The corners are transparent (a stadium), the centre of the straight is opaque.
		assert.equal(img.data[3], 0);
		const mid = (Math.floor(img.height / 2) * img.width + x0) * 4;
		assert.equal(img.data[mid + 3], 255);
	}
});

test('the finish and start/finish pills carry the chequered flag; the start pill does not', () => {
	const inkPixels = (kind: 'start' | 'finish' | 'startFinish') => {
		const img = startFinishPillImage(kind, false, 3);
		// Light basemap: the ink is white; count opaque white pixels left of the text.
		let n = 0;
		for (let y = 0; y < img.height; y++) {
			for (let x = 0; x < img.content[0]; x++) {
				const i = (y * img.width + x) * 4;
				if (img.data[i + 3] === 255 && img.data[i] === 255 && img.data[i + 1] === 255 && img.data[i + 2] === 255) n++;
			}
		}
		return n;
	};
	assert.equal(inkPixels('start'), 0);
	assert.ok(inkPixels('finish') > 50);
	assert.ok(inkPixels('startFinish') > 50);
	// The flag sits before the label, so a flagged pill is wider.
	assert.ok(startFinishPillImage('finish', false).width > startFinishPillImage('start', false).width);
});
