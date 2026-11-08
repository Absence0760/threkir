import { test } from 'node:test';
import assert from 'node:assert/strict';
import { courseGateBounds, courseGateGeoJSON, type DrawnGate } from './course_gate_layers';

// One metre is 8.993203637e-6 degrees of latitude, and of longitude on the
// equator (R = 6371008.8 m).
const M = 8.99320363724538e-6;

const start: DrawnGate = {
	which: 'start',
	courseId: 'c1',
	gate: { lat: 0, lng: 0, bearingDeg: 0, halfWidthM: 10 },
};
const finish: DrawnGate = {
	which: 'finish',
	courseId: 'c1',
	gate: { lat: 0, lng: 0, bearingDeg: 90, halfWidthM: 10 },
};

test('a start line is one segment with no arrow', () => {
	const fc = courseGateGeoJSON([start]);
	assert.equal(fc.features.length, 1);
	const f = fc.features[0];
	assert.deepEqual(f.properties, { which: 'start', kind: 'line', courseId: 'c1' });
	assert.equal(f.geometry.type, 'LineString');
	const [[lng0, lat0], [lng1, lat1]] = f.geometry.coordinates as number[][];
	// Northbound: the line runs west (left) to east (right), 10 m each side.
	assert.ok(Math.abs(lng0 + 10 * M) < 1e-12 && Math.abs(lng1 - 10 * M) < 1e-12);
	assert.ok(Math.abs(lat0) < 1e-12 && Math.abs(lat1) < 1e-12);
});

test('a finish line carries an arrow from its centre to the tip, with a chevron head', () => {
	const fc = courseGateGeoJSON([finish]);
	assert.equal(fc.features.length, 2);
	const arrow = fc.features[1];
	assert.deepEqual(arrow.properties, { which: 'finish', kind: 'arrow', courseId: 'c1' });
	assert.equal(arrow.geometry.type, 'MultiLineString');
	const [shaft, head] = arrow.geometry.coordinates as number[][][];
	// Eastbound, half-width 10: the shaft is the 20 m floor.
	assert.deepEqual(shaft[0], [0, 0]);
	assert.ok(Math.abs(shaft[1][0] - 20 * M) < 1e-12 && Math.abs(shaft[1][1]) < 1e-12);
	// The chevron's wings sit behind the tip (west of it), one each side.
	assert.equal(head.length, 3);
	assert.deepEqual(head[1], shaft[1]);
	assert.ok(head[0][0] < shaft[1][0] && head[2][0] < shaft[1][0]);
	assert.ok(head[0][1] * head[2][1] < 0);
});

test('bounds cover every line and arrow, and are null with nothing to draw', () => {
	assert.equal(courseGateBounds([]), null);
	const [w, s, e, n] = courseGateBounds([start, finish])!;
	assert.ok(Math.abs(w + 10 * M) < 1e-12);
	assert.ok(Math.abs(e - 20 * M) < 1e-12);
	assert.ok(Math.abs(s + 10 * M) < 1e-12);
	assert.ok(Math.abs(n - 10 * M) < 1e-12);
});
