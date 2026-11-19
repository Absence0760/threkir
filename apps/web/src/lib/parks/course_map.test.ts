import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { badgeAtOverview, courseBoxGates, courseKeyKinds, courseBoxInstruction, distinctStarts, finishesAtStart } from './course_map';

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

const segment = {
	start_gate_lat: 37.3,
	start_gate_lng: -77.5,
	start_gate_bearing_deg: 10,
	start_gate_half_width_m: 15,
	end_gate_lat: 37.3,
	end_gate_lng: -77.5,
	end_gate_bearing_deg: 190,
	end_gate_half_width_m: 15,
};

test('courseBoxGates: the stored start and end lines, end as the finish', () => {
	assert.deepEqual(courseBoxGates(segment), {
		start: { lat: 37.3, lng: -77.5, bearingDeg: 10, halfWidthM: 15 },
		finish: { lat: 37.3, lng: -77.5, bearingDeg: 190, halfWidthM: 15 },
	});
});

test('courseBoxGates: a segment missing either line draws no boxes', () => {
	assert.equal(courseBoxGates({ ...segment, end_gate_bearing_deg: null }), null);
	assert.equal(courseBoxGates({ ...segment, start_gate_lat: null }), null);
});

test('courseBoxInstruction: an out-and-back is one green-and-red box, by the turn when it has one', () => {
	const gates = courseBoxGates(segment)!;
	assert.deepEqual(courseBoxInstruction(gates, false, null), { key: 'parks.boxesShared', params: { n: 1 } });
	assert.deepEqual(courseBoxInstruction(gates, true, null), { key: 'parks.boxesOutAndBack' });
	assert.deepEqual(courseBoxInstruction(gates, false, 2), { key: 'parks.boxesShared', params: { n: 2 } });
});

test('courseBoxInstruction: lines apart, or a loop at one spot, are a green box and a red box, laps counted', () => {
	const apart = courseBoxGates({ ...segment, end_gate_lat: north(37.3, 2000), end_gate_bearing_deg: 100 })!;
	assert.deepEqual(courseBoxInstruction(apart, false, 1), { key: 'parks.boxesApart', params: { n: 1 } });
	const loop = courseBoxGates({ ...segment, end_gate_bearing_deg: 10 })!;
	assert.deepEqual(courseBoxInstruction(loop, false, null), { key: 'parks.boxesApart', params: { n: 1 } });
	assert.deepEqual(courseBoxInstruction(loop, false, 2), { key: 'parks.boxesApart', params: { n: 2 } });
});

test('badgeAtOverview: a short lap shows every badge, a long one every 5th', () => {
	assert.deepEqual([1, 2, 3, 4, 5].map((k) => badgeAtOverview(k, 5)), [true, true, true, true, true]);
	assert.deepEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((k) => badgeAtOverview(k, 10)).every(Boolean), true);
	assert.deepEqual(
		[1, 4, 5, 6, 10, 15, 24, 25].map((k) => badgeAtOverview(k, 24.9)),
		[false, false, true, false, true, true, false, true],
	);
});

test('courseKeyKinds: the key names only what the map draws', () => {
	const base = { boxes: 'apart' as const, finishesAtStart: false, checkpointMarkers: 0, turnaround: false, badgesShown: false };
	assert.deepEqual(courseKeyKinds(base), ['startBox', 'finishBox', 'direction']);
	assert.deepEqual(courseKeyKinds({ ...base, boxes: 'merged', checkpointMarkers: 3, turnaround: true, badgesShown: true }), [
		'startFinishBox',
		'checkpoint',
		'turnaround',
		'distance',
		'direction',
	]);
	assert.deepEqual(courseKeyKinds({ ...base, boxes: 'none', finishesAtStart: true }), ['startFinish', 'direction']);
	assert.deepEqual(courseKeyKinds({ ...base, boxes: 'none' }), ['start', 'finish', 'direction']);
});
