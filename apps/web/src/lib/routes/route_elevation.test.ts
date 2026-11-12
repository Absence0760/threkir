import { test } from 'node:test';
import assert from 'node:assert/strict';

import { routeElevation } from './route_elevation';

const at = (ele: number | undefined, i: number) => ({ lat: 39.7 - i * 0.01, lng: -105, ele });

test('the climb is the stored figure, not a sum over the waypoints (issue #902)', () => {
	// The seeded Denver Marathon Route: 320 m stored, four waypoints that
	// climb 100 m between them. The page used to state both.
	const wps = [1600, 1640, 1680, 1700].map(at);
	const out = routeElevation(320, wps);
	assert.equal(out.gain, 320);
	assert.deepEqual(out.profile, [1600, 1640, 1680, 1700]);
	assert.equal(out.min, 1600);
	assert.equal(out.max, 1700);
});

test('a simplified line that dropped a summit still reports the stored climb and a consistent descent', () => {
	// Out over a 300 m hill and back to a start 20 m lower: the raw track
	// climbed 300 m, simplification kept only the endpoints and one shoulder.
	const wps = [100, 150, 80].map(at);
	const out = routeElevation(300, wps);
	assert.equal(out.gain, 300);
	assert.equal(out.loss, 320);
});

test('a loop descends what it climbs', () => {
	const out = routeElevation(85, [30, 70, 115, 95, 30].map(at));
	assert.equal(out.loss, 85);
});

test('no descent is stated when the stored climb is below the profile net rise', () => {
	const out = routeElevation(10, [18, 22, 26, 30].map(at));
	assert.equal(out.gain, 10);
	assert.equal(out.loss, null);
	assert.equal(out.max, 30);
});

test('a waypoint with no altitude is interpolated, not drawn at sea level', () => {
	const out = routeElevation(40, [at(1500, 0), at(undefined, 1), at(1540, 2)]);
	assert.deepEqual(out.profile, [1500, 1520, 1540]);
	assert.equal(out.min, 1500);
	assert.equal(out.loss, 0);
});

test('no profile, extremes or descent without altitude on the waypoints', () => {
	for (const wps of [[], [at(undefined, 0), at(undefined, 1)], [at(1600, 0), at(undefined, 1)]]) {
		const out = routeElevation(320, wps);
		assert.deepEqual(out, { gain: 320, profile: null, min: null, max: null, loss: null });
	}
});

test('a flat profile draws nothing', () => {
	const out = routeElevation(5, [10, 10, 10].map(at));
	assert.equal(out.profile, null);
	assert.equal(out.loss, null);
});

test('the stored climb is rounded once, the descent from the unrounded figure', () => {
	const out = routeElevation(99.6, [0, 50, 20].map(at));
	assert.equal(out.gain, 100);
	assert.equal(out.loss, 80);
});
