import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { distanceAtStripOffset, stripGeometry, stripX } from './strip_geometry.ts';

const climb = { startM: 250, endM: 750, gainM: 40, avgGradePct: 8, name: null };

test('the strip spans the full width and maps the climb to its distances', () => {
	const g = stripGeometry(
		[
			{ dM: 0, ele: 100 },
			{ dM: 500, ele: 140 },
			{ dM: 1000, ele: 100 },
		],
		[climb],
		1000,
		200,
		40,
	);
	assert.equal(g.line, 'M0,40 L100,0 L200,40');
	assert.equal(g.area, 'M0,40 L100,0 L200,40 L200,40 L0,40 Z');
	assert.deepEqual(
		g.climbs.map(({ x0, x1 }) => [x0, x1]),
		[[50, 150]],
	);
});

test('a flat course is centred, not stretched to the full height', () => {
	const g = stripGeometry(
		[
			{ dM: 0, ele: 100 },
			{ dM: 1000, ele: 102 },
		],
		[],
		1000,
		100,
		40,
	);
	assert.equal(g.line, 'M0,22 L100,18');
});

test('no elevation means an empty strip', () => {
	assert.deepEqual(stripGeometry([], [climb], 1000, 200, 40), { line: '', area: '', climbs: [] });
	assert.deepEqual(stripGeometry([{ dM: 0, ele: 1 }, { dM: 1, ele: 2 }], [], 0, 200, 40).line, '');
});

test('stripX clamps to the strip', () => {
	assert.equal(stripX(-10, 1000, 200), 0);
	assert.equal(stripX(2000, 1000, 200), 200);
	assert.equal(stripX(100, 0, 200), 0);
});

test('a pointer offset maps to a clamped distance', () => {
	assert.equal(distanceAtStripOffset(50, 200, 1000), 250);
	assert.equal(distanceAtStripOffset(-5, 200, 1000), 0);
	assert.equal(distanceAtStripOffset(500, 200, 1000), 1000);
	assert.equal(distanceAtStripOffset(50, 0, 1000), 0);
});
