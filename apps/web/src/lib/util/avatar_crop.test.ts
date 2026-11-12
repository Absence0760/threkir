import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	AVATAR_MAX_ZOOM,
	AVATAR_OUTPUT_MAX_PX,
	clampPan,
	clampZoom,
	cropRect,
	displayScale,
	initialCropState,
	normalizeQuarterTurns,
	outputSize,
	panBy,
	rezoom,
	rotate,
	rotatedSize,
} from './avatar_crop';

test('normalizeQuarterTurns wraps into 0..3 in both directions', () => {
	assert.deepEqual([-5, -1, 0, 1, 4, 7].map(normalizeQuarterTurns), [3, 3, 0, 1, 0, 3]);
});

test('rotatedSize swaps the sides on an odd quarter turn only', () => {
	assert.deepEqual(rotatedSize(400, 200, 0), { width: 400, height: 200 });
	assert.deepEqual(rotatedSize(400, 200, 1), { width: 200, height: 400 });
	assert.deepEqual(rotatedSize(400, 200, 2), { width: 400, height: 200 });
	assert.deepEqual(rotatedSize(400, 200, -1), { width: 200, height: 400 });
});

test('clampZoom bounds the zoom and treats a non-number as 1', () => {
	assert.equal(clampZoom(0.2), 1);
	assert.equal(clampZoom(2.5), 2.5);
	assert.equal(clampZoom(99), AVATAR_MAX_ZOOM);
	assert.equal(clampZoom(Number.NaN), 1);
});

test('displayScale fits the short side to the viewport at zoom 1', () => {
	assert.equal(displayScale({ width: 400, height: 200 }, 100, 1), 0.5);
	assert.equal(displayScale({ width: 400, height: 200 }, 100, 2), 1);
});

test('clampPan keeps the viewport covered', () => {
	// 400x200 shown at 0.5 is 200x100 in a 100 viewport: 50 px of slack each
	// side horizontally, none vertically.
	const r = { width: 400, height: 200 };
	assert.deepEqual(clampPan({ x: 80, y: 30 }, r, 100, 1), { x: 50, y: 0 });
	assert.deepEqual(clampPan({ x: -80, y: -30 }, r, 100, 1), { x: -50, y: 0 });
	assert.deepEqual(clampPan({ x: 10, y: 0 }, r, 100, 1), { x: 10, y: 0 });
});

test('the initial crop is the centred square of the short side', () => {
	assert.deepEqual(cropRect(initialCropState(400, 200, 100)), { x: 100, y: 0, size: 200 });
	assert.deepEqual(cropRect(initialCropState(200, 400, 100)), { x: 0, y: 100, size: 200 });
});

test('panning right reveals the left of the image', () => {
	const s = panBy(initialCropState(400, 200, 100), 50, 0);
	assert.deepEqual(cropRect(s), { x: 0, y: 0, size: 200 });
	const t = panBy(initialCropState(400, 200, 100), -999, 0);
	assert.deepEqual(cropRect(t), { x: 200, y: 0, size: 200 });
});

test('zoom shrinks the crop about the centre', () => {
	const s = rezoom(initialCropState(400, 200, 100), 2);
	assert.deepEqual(cropRect(s), { x: 150, y: 50, size: 100 });
});

test('rezoom scales the pan so the centred point stays put, then clamps', () => {
	const panned = panBy(initialCropState(400, 200, 100), 20, 0);
	const z = rezoom(panned, 2);
	assert.deepEqual(z.pan, { x: 40, y: 0 });
	const back = rezoom(rezoom(panBy(rezoom(initialCropState(400, 200, 100), 4), 0, 150), 4), 1);
	assert.deepEqual(back.pan, { x: 0, y: 0 });
});

test('a quarter turn swaps the crop space and keeps the pan with the image', () => {
	const s = rotate(initialCropState(400, 200, 100), 1);
	assert.equal(s.quarterTurns, 1);
	assert.deepEqual(cropRect(s), { x: 0, y: 100, size: 200 });

	// Panned to show the left end, then turned clockwise: the left end is now
	// the top, so the crop sits at the top of the rotated image.
	const left = rotate(panBy(initialCropState(400, 200, 100), 50, 0), 1);
	assert.deepEqual(left.pan, { x: 0, y: 50 });
	assert.deepEqual(cropRect(left), { x: 0, y: 0, size: 200 });

	const ccw = rotate(panBy(initialCropState(400, 200, 100), 50, 0), -1);
	assert.equal(ccw.quarterTurns, 3);
	assert.deepEqual(ccw.pan, { x: 0, y: -50 });
	assert.deepEqual(cropRect(ccw), { x: 0, y: 200, size: 200 });
});

test('four turns in either direction return to the start', () => {
	let s = panBy(rezoom(initialCropState(300, 500, 120), 2), 30, -40);
	const start = s;
	for (let i = 0; i < 4; i++) s = rotate(s, 1);
	assert.deepEqual(s, start);
	for (let i = 0; i < 4; i++) s = rotate(s, -1);
	assert.deepEqual(s, start);
});

test('cropRect stays inside the image for an off-range pan or zoom', () => {
	const s = { ...initialCropState(333, 777, 97), zoom: 9, pan: { x: 1e6, y: -1e6 }, quarterTurns: 3 };
	const r = cropRect(s);
	const rot = rotatedSize(333, 777, 3);
	assert.ok(r.x >= 0 && r.y >= 0);
	assert.ok(r.x + r.size <= rot.width && r.y + r.size <= rot.height);
	assert.equal(r.size, Math.round(333 / AVATAR_MAX_ZOOM));
});

test('a tiny image never produces a zero-sized crop', () => {
	assert.deepEqual(cropRect({ ...initialCropState(1, 1, 300), zoom: 4 }), { x: 0, y: 0, size: 1 });
});

test('outputSize caps at the avatar size and never upscales', () => {
	assert.equal(outputSize(3024), AVATAR_OUTPUT_MAX_PX);
	assert.equal(outputSize(200), 200);
	assert.equal(outputSize(199.6), 200);
	assert.equal(outputSize(0), 1);
});
