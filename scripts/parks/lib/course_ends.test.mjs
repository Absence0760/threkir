// The course-ends fetch boundary: the Overpass query and the checked parse
// the go-live gate reads offline.
// Run: node --test scripts/parks/lib/course_ends.test.mjs

import assert from 'node:assert/strict';
import test from 'node:test';

import { PARKING_KEPT, courseEndsQuery, parseCourseEnds, publicParking } from './course_ends.mjs';
import { ROAD_HIGHWAY_PATTERN } from './road_crossings.mjs';

const end = { lat: 37.5, lng: -77.5 };

test('the query asks for car parks and motor roads around every end', () => {
	const q = courseEndsQuery([end, { lat: 37.6, lng: -77.4 }], ROAD_HIGHWAY_PATTERN);
	assert.match(q, /nwr\(around:1500,37\.5000000,-77\.5000000\)\[amenity=parking\];/);
	assert.match(q, /way\(around:60,37\.6000000,-77\.4000000\)\[highway~"\^\(motorway\|/);
	assert.match(q, /out center tags;[\s\S]*out geom tags;/);
});

test('car parks are kept nearest first with their distance; roads within 60 m with their line', () => {
	const body = {
		elements: [
			{ type: 'way', id: 3, center: { lat: 37.505, lon: -77.5 }, tags: { amenity: 'parking', fee: 'yes', surface: 'gravel' } },
			{ type: 'node', id: 4, lat: 37.501, lon: -77.5, tags: { amenity: 'parking', access: 'private' } },
			{ type: 'node', id: 4, lat: 37.501, lon: -77.5, tags: { amenity: 'parking', access: 'private' } },
			{ type: 'node', id: 5, lat: 37.52, lon: -77.5, tags: { amenity: 'parking', access: 'permit' } },
			{ type: 'way', id: 7, tags: { highway: 'residential', name: 'Park Road', maxspeed: '25 mph' }, geometry: [{ lat: 37.5003, lon: -77.501 }, { lat: 37.5003, lon: -77.499 }] },
			{ type: 'way', id: 8, tags: { highway: 'service' }, geometry: [{ lat: 37.6, lon: -77.4 }, { lat: 37.6001, lon: -77.4 }] },
		],
	};
	const [e] = parseCourseEnds(body, [end]);
	assert.deepEqual(e.parking.map((p) => [p.id, p.m]), [['node/4', 111], ['way/3', 556]], 'node 5, 2.2 km off, is past the search radius');
	assert.deepEqual(e.parking[1].tags, { amenity: 'parking', fee: 'yes' }, 'only the tags the gate reads');
	assert.deepEqual(e.roads.map((r) => [r.id, r.name, r.highway, r.line.length]), [[7, 'Park Road', 'residential', 2]]);
	assert.equal(publicParking(e.parking[0]), false);
	assert.equal(publicParking(e.parking[1]), true);
	assert.equal(publicParking({ id: 'n', lat: 0, lng: 0, m: 0, tags: { amenity: 'parking', access: 'permit' } }), true, 'a state park day-use pass');
});

test(`at most ${PARKING_KEPT} car parks are kept per end`, () => {
	const elements = Array.from({ length: 6 }, (_, i) => ({ type: 'node', id: i + 1, lat: 37.5 + (i + 1) * 0.001, lon: -77.5, tags: { amenity: 'parking' } }));
	assert.equal(parseCourseEnds({ elements }, [end])[0].parking.length, PARKING_KEPT);
});

test('a malformed response stops the fetch', () => {
	assert.throws(() => parseCourseEnds({}, [end]), /no elements array/);
	assert.throws(() => parseCourseEnds({ elements: [{ type: 'node', id: -1, tags: { amenity: 'parking' } }] }, [end]), /positive integer/);
	assert.throws(() => parseCourseEnds({ elements: [{ type: 'node', id: 1, lat: 99, lon: 0, tags: { amenity: 'parking' } }] }, [end]), /valid coordinate/);
	assert.throws(() => parseCourseEnds({ elements: [{ type: 'way', id: 1, tags: { highway: 'footway' }, geometry: [] }] }, [end]), /not a motor road/);
	assert.throws(() => parseCourseEnds({ elements: [{ type: 'way', id: 1, tags: { highway: 'service' } }] }, [end]), /no geometry/);
	assert.throws(() => parseCourseEnds({ elements: [{ type: 'area', id: 1 }] }, [end]), /unexpected Overpass element type/);
});
