import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { VIDEO_HEIGHT, VIDEO_WIDTH } from '#lib/video/frame_clock.ts';
import { OVERVIEW_PADDING_PX } from './overview.ts';
import { videoOverlayLayout } from './video_overlay.ts';
import { VIDEO_REFERENCE_CSS_WIDTH, videoMapViewport, videoOverviewPadding } from './video_viewport.ts';

// MapLibre's own sizing: the container floored to whole CSS px, the canvas
// rounded to pixelRatio times that (Map._containerDimensions / _resizeCanvas).
function canvasSize(v: { cssWidth: number; cssHeight: number; pixelRatio: number }): [number, number] {
	return [
		Math.round(v.pixelRatio * Math.floor(v.cssWidth)),
		Math.round(v.pixelRatio * Math.floor(v.cssHeight)),
	];
}

test('the 1080x1920 video renders its map at a phone CSS size, scaled up', () => {
	const v = videoMapViewport(VIDEO_WIDTH, VIDEO_HEIGHT);
	assert.equal(v.cssWidth, 387);
	assert.equal(v.cssHeight, 688);
	assert.equal(v.pixelRatio, 1080 / 387);
});

test('the drawn canvas is exactly the video size, so it copies in 1:1', () => {
	assert.deepEqual(canvasSize(videoMapViewport(VIDEO_WIDTH, VIDEO_HEIGHT)), [VIDEO_WIDTH, VIDEO_HEIGHT]);
	for (const [w, h] of [
		[1080, 1920],
		[1920, 1080],
		[1080, 1080],
		[720, 1280],
		[1080, 1350],
	]) {
		const v = videoMapViewport(w, h);
		assert.equal(Number.isInteger(v.cssWidth) && Number.isInteger(v.cssHeight), true, `${w}x${h}`);
		assert.deepEqual(canvasSize(v), [w, h], `${w}x${h}`);
	}
});

test('the map shows the ground the preview shows, within a few percent', () => {
	const v = videoMapViewport(VIDEO_WIDTH, VIDEO_HEIGHT);
	assert.ok(Math.abs(v.cssWidth / VIDEO_REFERENCE_CSS_WIDTH - 1) < 0.02, `${v.cssWidth}`);
});

test('a video narrower than the reference is not scaled down', () => {
	const v = videoMapViewport(300, 300);
	assert.equal(v.cssWidth, 300);
	assert.equal(v.pixelRatio, 1);
});

test('the overview padding converts the scrims to CSS px and keeps the preview side margin', () => {
	const L = videoOverlayLayout(VIDEO_WIDTH, VIDEO_HEIGHT);
	const v = videoMapViewport(VIDEO_WIDTH, VIDEO_HEIGHT);
	const p = videoOverviewPadding(L, v.pixelRatio);
	assert.equal(p.top * v.pixelRatio, L.topScrim);
	assert.equal(p.bottom * v.pixelRatio, L.bottomScrim);
	assert.equal(p.left, OVERVIEW_PADDING_PX);
	assert.equal(p.right, OVERVIEW_PADDING_PX);
});

test('the overview still has a band to fit the whole course into', () => {
	const L = videoOverlayLayout(VIDEO_WIDTH, VIDEO_HEIGHT);
	const v = videoMapViewport(VIDEO_WIDTH, VIDEO_HEIGHT);
	const p = videoOverviewPadding(L, v.pixelRatio);
	const bandW = v.cssWidth - p.left - p.right;
	const bandH = v.cssHeight - p.top - p.bottom;
	// The band between the scrims, in video pixels, is where the course lands.
	assert.equal(Math.round(bandH * v.pixelRatio), VIDEO_HEIGHT - L.topScrim - L.bottomScrim);
	assert.ok(bandW > 200 && bandH > 200, `${bandW}x${bandH}`);
});
