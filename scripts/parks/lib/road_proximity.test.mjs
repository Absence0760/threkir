// Run: node --test scripts/parks/lib/road_proximity.test.mjs

import assert from 'node:assert/strict';
import test from 'node:test';

import { REVIEW_WITHIN_M, bearingDeg, distanceToLineM, endReport, nearestRoad, offsetPoint, osmBbox } from './road_proximity.mjs';

const M = 1 / 111_195; // ~degrees of latitude per metre

// A trail running due north for 200 m from (0, 0).
const trail = Array.from({ length: 11 }, (_, i) => ({ lat: i * 20 * M, lng: 0 }));
const end = trail[trail.length - 1];

test('offsetPoint and bearingDeg agree on north and east', () => {
	const north = offsetPoint({ lat: 0, lng: 0 }, 0, 100);
	assert.ok(Math.abs(north.lat - 100 * M) < 1e-7 && north.lng === 0);
	assert.equal(Math.round(bearingDeg({ lat: 0, lng: 0 }, north)), 0);
	assert.equal(Math.round(bearingDeg({ lat: 0, lng: 0 }, offsetPoint({ lat: 0, lng: 0 }, 90, 100))), 90);
});

test('distanceToLineM measures to the nearest segment, not the nearest vertex', () => {
	const road = [{ lat: -100 * M, lng: 10 * M }, { lat: 100 * M, lng: 10 * M }];
	assert.ok(Math.abs(distanceToLineM({ lat: 0, lng: 0 }, road) - 10) < 0.1);
});

test('nearestRoad skips trails and keeps motor roads, links included', () => {
	const p = { lat: 0, lng: 0 };
	const roads = [
		{ name: 'Trail', highway: 'footway', line: [p, { lat: M, lng: 0 }] },
		{ name: 'Ramp', highway: 'primary_link', line: [{ lat: 0, lng: 20 * M }, { lat: M, lng: 20 * M }] },
	];
	assert.equal(nearestRoad(p, roads)?.road.name, 'Ramp');
	assert.equal(nearestRoad(p, [roads[0]]), null);
});

test('a finish whose runout reaches a road across its path is flagged', () => {
	// A road crossing the trail 10 m past its end.
	const ahead = end.lat + 10 * M;
	const roads = [{ name: 'Parkway', highway: 'secondary', line: [{ lat: ahead, lng: -100 * M }, { lat: ahead, lng: 100 * M }] }];
	const r = endReport(trail, 'finish', roads);
	assert.equal(r.review, true);
	assert.ok((r.atRunout?.m ?? Infinity) < 1, 'the runout lands on the road');
});

test('a finish beside a parallel road is not flagged when the runout stays as far from it', () => {
	// A highway 20 m east of the whole trail, running alongside.
	const roads = [{ name: 'Route 5', highway: 'trunk', line: [{ lat: -100 * M, lng: 20 * M }, { lat: 400 * M, lng: 20 * M }] }];
	const r = endReport(trail, 'finish', roads);
	assert.ok(Math.abs((r.atEnd?.m ?? 0) - 20) < 0.5);
	assert.ok((r.atRunout?.m ?? 0) > REVIEW_WITHIN_M);
	assert.equal(r.review, false);
});

test('a start is measured behind it, where runners wait', () => {
	// A road crossing 10 m south of the start, behind it.
	const behind = -10 * M;
	const roads = [{ name: 'Lot road', highway: 'service', line: [{ lat: behind, lng: -100 * M }, { lat: behind, lng: 100 * M }] }];
	const r = endReport(trail, 'start', roads);
	assert.equal(r.review, true);
	assert.ok(r.runout.lat < 0, 'the runout point is south of the start');
});

test('osmBbox boxes a real point at OSM precision and refuses anything else', () => {
	assert.equal(osmBbox({ lat: 37.5, lng: -77.25 }, 0.0008), '-77.2508000,37.4992000,-77.2492000,37.5008000');
	assert.equal(osmBbox({ lat: 37.123456789, lng: -77.987654321 }, 0), '-77.9876543,37.1234568,-77.9876543,37.1234568');
	for (const bad of [{ lat: 91, lng: 0 }, { lat: 0, lng: -181 }, { lat: Number.NaN, lng: 0 }, { lat: '37', lng: 0 }, null]) {
		assert.throws(() => osmBbox(/** @type {any} */ (bad), 0.0008), /must be a number/);
	}
	assert.throws(() => osmBbox({ lat: 0, lng: 0 }, 5), /halfDeg/);
});
