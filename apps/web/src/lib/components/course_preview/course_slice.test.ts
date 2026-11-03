import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { buildFlyoverPath } from '#lib/routes/flyover_path.ts';
import { sliceCourse } from './course_slice.ts';

const path = buildFlyoverPath([
	{ lat: 0, lng: 0, ele: null },
	{ lat: 0, lng: 0.01, ele: null },
	{ lat: 0, lng: 0.02, ele: null },
	{ lat: 0, lng: 0.03, ele: null },
]);
const seg = path.cumM[1];

test('a slice keeps the interior points and interpolates both ends', () => {
	const s = sliceCourse(path, seg / 2, seg * 2.5);
	assert.equal(s.length, 4);
	assert.ok(Math.abs(s[0][0] - 0.005) < 1e-9);
	assert.deepEqual(s[1], [0.01, 0]);
	assert.deepEqual(s[2], [0.02, 0]);
	assert.ok(Math.abs(s[3][0] - 0.025) < 1e-9);
});

test('a slice inside one segment is just its two ends', () => {
	const s = sliceCourse(path, seg * 0.2, seg * 0.6);
	assert.equal(s.length, 2);
});

test('an empty or reversed range, or a one-point path, slices nothing', () => {
	assert.deepEqual(sliceCourse(path, 500, 500), []);
	assert.deepEqual(sliceCourse(path, 900, 100), []);
	assert.deepEqual(sliceCourse(buildFlyoverPath([{ lat: 1, lng: 1, ele: null }]), 0, 10), []);
});
