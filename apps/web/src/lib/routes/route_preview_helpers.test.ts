// Unit tests for the pure helpers exported from RouteTrackPreview.
// Static-map URL construction has to round-trip the polyline through
// MapTiler's `path=` parameter and downsample very long routes; pin
// the contract so a tweak to the encoding doesn't silently break
// every route preview.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

// We need to import the helpers from the Svelte module. Svelte 5
// compiles the `<script context="module">` (or `<script module>`)
// block into a re-exportable module, and `tsx --test` will route
// through svelte-package's resolver. For test purposes we point at
// the same .svelte file — the named exports are visible.
import { buildStaticMapUrl, MAX_PREVIEW_POINTS, previewPolyline, thumbnailSize } from './static_map';

const KEY = 'test-key-123';

test('previewPolyline returns a short track unchanged, at its raw fixes when it has no smoothed ones', () => {
	const pts = [
		{ lat: 1, lng: 1 },
		{ lat: 2, lng: 2 },
		{ lat: 3, lng: 3 },
	];
	assert.deepEqual(previewPolyline(pts), pts);
});

test('previewPolyline draws the smoothed line when the track carries one', () => {
	const pts = [
		{ lat: 1, lng: 1, smoothedLat: 1.5, smoothedLng: 1.25 },
		{ lat: 2, lng: 2, smoothedLat: null, smoothedLng: null },
	];
	assert.deepEqual(previewPolyline(pts), [
		{ lat: 1.5, lng: 1.25 },
		{ lat: 2, lng: 2 },
	]);
});

test('previewPolyline fits the cap, keeps both ends, and keeps a real corner a jittery track turns', () => {
	// An L: 500 fixes ~10 m apart east, then 500 north, each with ~3 m of
	// alternating jitter. Picking every Nth fix kept the jitter and could land
	// up to ~80 m either side of the corner; simplifying keeps the corner.
	const M = 1 / 111_320;
	const pts = [];
	for (let i = 0; i < 1000; i++) {
		const j = (i % 2 ? 3 : -3) * M;
		pts.push(i < 500 ? { lat: j, lng: i * 10 * M } : { lat: (i - 499) * 10 * M, lng: 4990 * M + j });
	}
	const out = previewPolyline(pts);
	assert.ok(out.length <= MAX_PREVIEW_POINTS, `${out.length} points`);
	assert.deepEqual(out[0], { lat: pts[0].lat, lng: pts[0].lng });
	assert.deepEqual(out[out.length - 1], { lat: pts[999].lat, lng: pts[999].lng });
	const corner = { lat: 0, lng: 4990 * M };
	const nearest = Math.min(...out.map((p) => Math.hypot(p.lat - corner.lat, p.lng - corner.lng) / M));
	assert.ok(nearest < 15, `nearest kept point is ${nearest.toFixed(1)} m from the corner`);
	// The jitter is gone: a straight leg collapses to a handful of points.
	assert.ok(out.length < 20, `${out.length} points for two straight legs`);
});

test('thumbnailSize requests the box it is drawn into: width in 40 px steps, height at the box aspect', () => {
	// 553x128 rounds the width to 560 and keeps the 4.32:1 shape, so `cover`
	// scales the image into the box rather than cropping the route's edges.
	assert.deepEqual(thumbnailSize(553, 128), { w: 560, h: 130 });
	assert.deepEqual(thumbnailSize(354, 128), { w: 360, h: 130 });
	assert.deepEqual(thumbnailSize(560, 160), { w: 560, h: 160 });
	for (const [bw, bh] of [[553, 128], [354, 128], [912, 160], [301, 301]]) {
		const { w, h } = thumbnailSize(bw, bh);
		assert.ok(Math.abs(w / h - bw / bh) < 0.02, `${bw}x${bh} -> ${w}x${h} changes the shape`);
	}
	assert.deepEqual(thumbnailSize(10, 10), { w: 40, h: 40 });
	assert.deepEqual(thumbnailSize(5000, 300), { w: 1024, h: 61 });
});

test('buildStaticMapUrl returns null when key missing', () => {
	const out = buildStaticMapUrl(
		[
			{ lat: 1, lng: 2 },
			{ lat: 3, lng: 4 },
		],
		{ w: 220, h: 140, style: 'streets-v2', key: '', stroke: '#F2A07B' },
	);
	assert.equal(out, null, 'must return null when no key — caller falls back to SVG');
});

test('buildStaticMapUrl returns null when fewer than 2 points', () => {
	const out = buildStaticMapUrl([{ lat: 1, lng: 2 }], {
		w: 220,
		h: 140,
		style: 'streets-v2',
		key: KEY,
		stroke: '#F2A07B',
	});
	assert.equal(out, null, 'single-waypoint routes have no polyline to draw');
});

test('buildStaticMapUrl includes the key, dimensions, style, and path', () => {
	const out = buildStaticMapUrl(
		[
			{ lat: 51.5074, lng: -0.1276 },
			{ lat: 51.5085, lng: -0.1284 },
		],
		{ w: 220, h: 140, style: 'streets-v2', key: KEY, stroke: '#F2A07B' },
	)!;
	assert.ok(out.startsWith('https://api.maptiler.com/maps/streets-v2/static/auto/'));
	assert.match(out, /\/220x140@2x\.png/);
	assert.match(out, new RegExp(`key=${KEY}`));
	// Path includes a transparent fill (so closed loops don't render
	// as a black polygon), the brand stroke (URL-encoded #), width,
	// and coordinates.
	assert.match(out, /fill:%23ffffff00\|/);
	assert.match(out, /stroke:%23F2A07B\|width:3\|/);
	assert.match(out, /-0\.12760,51\.50740/);
	assert.match(out, /-0\.12840,51\.50850/);
});
