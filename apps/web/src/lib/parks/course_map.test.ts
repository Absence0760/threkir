import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { distinctStarts, finishesAtStart } from './course_map';

const M_PER_DEG_LAT = 111_320;
const north = (lat: number, m: number) => lat + m / M_PER_DEG_LAT;

test('distinctStarts: courses from one trailhead share a start', () => {
	const a = [{ lat: 37.3, lng: -77.5 }, { lat: 37.31, lng: -77.5 }];
	const b = [{ lat: north(37.3, 40), lng: -77.5 }, { lat: 37.29, lng: -77.5 }];
	const c = [{ lat: north(37.3, 500), lng: -77.5 }, { lat: 37.29, lng: -77.5 }];
	assert.deepEqual(distinctStarts([a, b, c]), [
		{ lat: 37.3, lng: -77.5 },
		{ lat: north(37.3, 500), lng: -77.5 },
	]);
});

test('distinctStarts: a course with no line, or a broken first point, adds no start', () => {
	assert.deepEqual(distinctStarts([[], [{ lat: Number.NaN, lng: 0 }]]), []);
});

test('finishesAtStart: a loop closes, an out-and-back to elsewhere does not', () => {
	assert.equal(finishesAtStart([{ lat: 37.3, lng: -77.5 }, { lat: 37.31, lng: -77.5 }, { lat: north(37.3, 10), lng: -77.5 }]), true);
	assert.equal(finishesAtStart([{ lat: 37.3, lng: -77.5 }, { lat: north(37.3, 1000), lng: -77.5 }]), false);
	assert.equal(finishesAtStart([{ lat: 37.3, lng: -77.5 }]), false);
});
