import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	ROUTE_ART_MAX_POINTS,
	artAnchorIndices,
	densifyLine,
	drawingFidelity,
	fidelityToleranceM,
	fidelityVerdict,
	planRouteBatches,
	polylineLengthM,
	prepareStroke,
	routeArtBatchPath,
	sampleAlong,
	sliceAtAnchors,
	stitchPolylines,
	type LngLat,
} from './route_art';

// Twin of apps/mobile_android/test/route_art_test.dart — same cases, same
// expected values.

/// A hand-drawn square of ~1 km sides at London's latitude, stopped one
/// step short of its start so the loop-closing rule has work to do.
function square(): LngLat[] {
	const out: LngLat[] = [];
	const lng0 = -0.1;
	const lat0 = 51.5;
	const dLng = 0.0144;
	const dLat = 0.009;
	for (let i = 0; i <= 40; i++) out.push([lng0 + (dLng * i) / 40, lat0]);
	for (let i = 1; i <= 40; i++) out.push([lng0 + dLng, lat0 + (dLat * i) / 40]);
	for (let i = 1; i <= 40; i++) out.push([lng0 + dLng * (1 - i / 40), lat0 + dLat]);
	for (let i = 1; i <= 39; i++) out.push([lng0, lat0 + dLat * (1 - i / 40)]);
	return out;
}

function prepared(): LngLat[] {
	const p = prepareStroke(square());
	assert.ok(p.ok);
	return p.points;
}

test('prepareStroke closes a nearly-closed square and keeps its corners', () => {
	const p = prepareStroke(square());
	assert.ok(p.ok);
	assert.equal(p.closed, true);
	assert.equal(p.points.length, 69);
	assert.equal(p.spacingM, 60);
	assert.equal(Math.round(p.lengthM), 3970);
	assert.deepEqual(p.points[0], [-0.1, 51.5]);
	assert.deepEqual(p.points[p.points.length - 1], [-0.1, 51.5]);
	for (const corner of [
		[-0.0856, 51.5],
		[-0.0856, 51.509],
		[-0.1, 51.509],
	]) {
		assert.ok(
			p.points.some((q) => Math.abs(q[0] - corner[0]) < 1e-9 && Math.abs(q[1] - corner[1]) < 1e-9),
			`corner ${corner}`,
		);
	}
});

test('prepareStroke leaves an open stroke open', () => {
	const line: LngLat[] = [];
	for (let i = 0; i <= 20; i++) line.push([(0.01 * i) / 20, 0]);
	const p = prepareStroke(line);
	assert.ok(p.ok);
	assert.equal(p.closed, false);
	assert.deepEqual(p.points[p.points.length - 1], [0.01, 0]);
	assert.equal(p.points.length, 20);
});

test('prepareStroke drops non-finite, out-of-range and jitter points', () => {
	const line: LngLat[] = [
		[0, 0],
		[NaN, 0],
		[0.000001, 0],
		[200, 0],
		[0, 95],
		[0.005, 0],
	];
	const p = prepareStroke(line);
	assert.ok(p.ok);
	assert.deepEqual(p.points[0], [0, 0]);
	assert.deepEqual(p.points[p.points.length - 1], [0.005, 0]);
	assert.ok(p.points.every(([lng, lat]) => Number.isFinite(lng) && Math.abs(lat) <= 90));
});

test('prepareStroke rejects a stroke too short or too long to route', () => {
	assert.deepEqual(prepareStroke([]), { ok: false, reason: 'too_short' });
	assert.deepEqual(
		prepareStroke([
			[0, 0],
			[0.001, 0],
		]),
		{ ok: false, reason: 'too_short' },
	);
	assert.deepEqual(
		prepareStroke([
			[0, 0],
			[1, 0],
		]),
		{ ok: false, reason: 'too_long' },
	);
});

test('prepareStroke widens the spacing to stay within the point budget', () => {
	const line: LngLat[] = [];
	for (let i = 0; i <= 500; i++) line.push([i * 0.0009, 10 + (i % 2) * 0.00001]);
	const p = prepareStroke(line);
	assert.ok(p.ok);
	assert.ok(p.points.length <= ROUTE_ART_MAX_POINTS);
	assert.equal(p.points.length, 271);
	assert.equal(p.spacingM, 183.10546875);
});

test('densifyLine splits a segment evenly and keeps both ends', () => {
	const out = densifyLine(
		[
			[0, 0],
			[0.001, 0],
		],
		50,
	);
	assert.equal(out.length, 4);
	assert.deepEqual(out[0], [0, 0]);
	assert.deepEqual(out[3], [0.001, 0]);
	assert.ok(Math.abs(out[1][0] - 0.001 / 3) < 1e-15);
});

test('densifyLine interpolates across the antimeridian the short way', () => {
	const out = densifyLine(
		[
			[179.999, 0],
			[-179.999, 0],
		],
		100,
	);
	assert.equal(out.length, 4);
	for (const [lng] of out) assert.ok(Math.abs(lng) > 179.99, `lng ${lng}`);
});

test('planRouteBatches shares each seam point and caps every call', () => {
	assert.deepEqual(planRouteBatches(296), [
		{ start: 0, end: 59 },
		{ start: 59, end: 118 },
		{ start: 118, end: 177 },
		{ start: 177, end: 236 },
		{ start: 236, end: 295 },
	]);
	assert.deepEqual(planRouteBatches(60), [{ start: 0, end: 59 }]);
	assert.deepEqual(planRouteBatches(61), [
		{ start: 0, end: 59 },
		{ start: 59, end: 60 },
	]);
	assert.deepEqual(planRouteBatches(1), []);
	assert.deepEqual(planRouteBatches(5, 1), []);
});

test('routeArtBatchPath names every point and gives each a radius', () => {
	assert.equal(
		routeArtBatchPath(
			[
				[-0.1, 51.5],
				[-0.0991, 51.5007],
			],
			'foot',
			150,
		),
		'/route/v1/foot/-0.1,51.5;-0.0991,51.5007?overview=full&geometries=geojson&radiuses=150;150',
	);
});

test('stitchPolylines drops a duplicated seam point only', () => {
	const out = stitchPolylines([
		[
			[0, 0],
			[0.001, 0],
		],
		[
			[0.001, 0],
			[0.002, 0],
		],
		[
			[0.003, 0],
			[0.004, 0],
		],
	]);
	assert.deepEqual(out, [
		[0, 0],
		[0.001, 0],
		[0.002, 0],
		[0.003, 0],
		[0.004, 0],
	]);
});

test('sampleAlong spaces samples by distance and includes both ends', () => {
	const out = sampleAlong(
		[
			[0, 0],
			[0.001, 0],
			[0.001, 0.001],
		],
		5,
	);
	assert.equal(out.length, 5);
	assert.deepEqual(out[0], [0, 0]);
	assert.deepEqual(out[2], [0.001, 0]);
	assert.ok(Math.abs(out[4][1] - 0.001) < 1e-15);
	assert.deepEqual(sampleAlong([], 5), []);
	assert.deepEqual(sampleAlong([[1, 2]], 2), [
		[1, 2],
		[1, 2],
	]);
});

test('fidelityToleranceM scales with the drawing and clamps', () => {
	assert.equal(Math.round(fidelityToleranceM(prepared()) * 1000) / 1000, 70.62);
	assert.equal(
		fidelityToleranceM([
			[0, 0],
			[0.0001, 0],
		]),
		25,
	);
	assert.equal(
		fidelityToleranceM([
			[0, 0],
			[0.5, 0.5],
		]),
		120,
	);
});

test('drawingFidelity scores a route on the drawing as a perfect match', () => {
	const pts = prepared();
	const f = drawingFidelity(pts, pts);
	assert.ok(f);
	assert.equal(f.score, 100);
	assert.equal(f.verdict, 'close');
	assert.equal(f.meanOffsetM, 0);
	assert.equal(f.lengthRatio, 1);
});

test('drawingFidelity tolerates a route one street over', () => {
	const pts = prepared();
	const shifted = pts.map(([lng, lat]) => [lng, lat + 0.0003] as LngLat);
	const f = drawingFidelity(pts, shifted);
	assert.ok(f);
	assert.equal(f.score, 100);
	assert.equal(Math.round(f.maxOffsetM), 33);
	assert.equal(Math.round(f.meanOffsetM), 17);
});

test('drawingFidelity refuses a route that skips half the drawing', () => {
	const pts = prepared();
	const f = drawingFidelity(pts, pts.slice(0, Math.floor(pts.length / 2)));
	assert.ok(f);
	assert.equal(f.coverage, 53 / 101);
	assert.equal(f.precision, 1);
	assert.equal(f.score, 52);
	assert.equal(f.verdict, 'poor');
});

test('drawingFidelity refuses a route that detours far off the drawing', () => {
	const pts = prepared();
	const detour: LngLat[] = [...pts, [-0.1, 51.48], [-0.1, 51.5]];
	const f = drawingFidelity(pts, detour);
	assert.ok(f);
	assert.equal(f.coverage, 1);
	assert.ok(f.precision < 0.6, `precision ${f.precision}`);
	assert.equal(f.verdict, 'poor');
});

test('drawingFidelity returns null when either line is degenerate', () => {
	assert.equal(drawingFidelity([[0, 0]], prepared()), null);
	assert.equal(drawingFidelity(prepared(), []), null);
	assert.equal(
		drawingFidelity(prepared(), [
			[0, 0],
			[0, 0],
		]),
		null,
	);
});

test('fidelityVerdict bands the score', () => {
	assert.equal(fidelityVerdict(100), 'close');
	assert.equal(fidelityVerdict(85), 'close');
	assert.equal(fidelityVerdict(84), 'rough');
	assert.equal(fidelityVerdict(60), 'rough');
	assert.equal(fidelityVerdict(59), 'poor');
});

test('artAnchorIndices keeps both ends and caps the count', () => {
	const pts = prepared();
	assert.deepEqual(artAnchorIndices(pts), [0, 9, 18, 26, 35, 43, 52, 60, 68]);
	const capped = artAnchorIndices(pts, 50, 4);
	assert.deepEqual(capped, [0, 23, 46, 68]);
	assert.deepEqual(artAnchorIndices([]), []);
	assert.deepEqual(artAnchorIndices([[0, 0]]), [0]);
	assert.deepEqual(
		artAnchorIndices([
			[0, 0],
			[0.001, 0],
		]),
		[0, 1],
	);
});

test('sliceAtAnchors cuts the line into pieces that share their ends', () => {
	const pts = prepared();
	const anchors = artAnchorIndices(pts);
	const slices = sliceAtAnchors(pts, anchors);
	assert.equal(slices.length, anchors.length - 1);
	assert.equal(Math.round(slices.reduce((s, part) => s + polylineLengthM(part), 0)), Math.round(polylineLengthM(pts)));
	for (let j = 1; j < slices.length; j++) {
		assert.deepEqual(slices[j][0], slices[j - 1][slices[j - 1].length - 1]);
	}
});
