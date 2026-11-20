// Unit tests for where a course crosses a motor road at grade.
// Run: node --test scripts/parks/lib/road_crossings.test.mjs

import assert from 'node:assert/strict';
import test from 'node:test';

import {
	ROAD_HIGHWAY_PATTERN,
	ROAD_SIGNAL_NEAR_M,
	crossableRoad,
	parseRoadCrossings,
	roadCrossingAt,
	signalAtNode,
} from './road_crossings.mjs';

// The course runs east along the equator through node 2; a road runs north-south through it.
const here = { lat: 0, lon: 0.0005 };
const prev = { id: 1, lat: 0, lon: 0 };
const next = { id: 3, lat: 0, lon: 0.001 };
const north = { node: 21, lat: 0.0003, lon: 0.0005 };
const south = { node: 22, lat: -0.0003, lon: 0.0005 };

/** @param {Record<string, string>} tags @param {import('./road_crossings.mjs').RoadArm[]} arms @param {number} [id] */
const road = (tags, arms, id = 50) => ({ id, tags, arms });

test('crossableRoad takes motor roads cars use, and named service roads only', () => {
	assert.equal(crossableRoad({ highway: 'residential' }), true);
	assert.equal(crossableRoad({ highway: 'secondary_link', name: 'Ramp' }), true);
	assert.equal(crossableRoad({ highway: 'footway' }), false);
	assert.equal(crossableRoad({ highway: 'cycleway', name: 'Bike Path' }), false);
	assert.equal(crossableRoad({ highway: 'service' }), false);
	assert.equal(crossableRoad({ highway: 'service', name: 'Park Road' }), true);
	assert.equal(crossableRoad({ highway: 'service', service: 'driveway', name: 'Smith Lane' }), false);
	assert.equal(crossableRoad({ highway: 'service', service: 'parking_aisle', name: 'Lot A' }), false);
	assert.equal(crossableRoad({ highway: 'tertiary', bridge: 'yes' }), false);
	assert.equal(crossableRoad({ highway: 'tertiary', bridge: 'no' }), true);
	assert.equal(crossableRoad({ highway: 'primary', tunnel: 'yes' }), false);
	assert.equal(crossableRoad({ highway: 'unclassified', motor_vehicle: 'no' }), false);
	assert.equal(crossableRoad({ highway: 'unclassified', access: 'no' }), false);
	assert.ok(new RegExp(ROAD_HIGHWAY_PATTERN).test('motorway_link'));
	assert.ok(!new RegExp(ROAD_HIGHWAY_PATTERN).test('footway'));
});

test('signalAtNode reads the three ways OSM tags a signal on a crossing', () => {
	assert.equal(signalAtNode({ highway: 'traffic_signals' }), true);
	assert.equal(signalAtNode({ highway: 'crossing', crossing: 'traffic_signals' }), true);
	assert.equal(signalAtNode({ highway: 'crossing', 'crossing:signals': 'yes' }), true);
	assert.equal(signalAtNode({ highway: 'crossing', crossing: 'marked' }), false);
	assert.equal(signalAtNode({ highway: 'crossing', crossing: 'unmarked' }), false);
	assert.equal(signalAtNode({}), false);
});

test('a road with arms either side of the course is crossed, named or not', () => {
	const named = { tags: {}, roads: [road({ highway: 'secondary', name: 'Hunter Mill Road' }, [north, south])] };
	assert.deepEqual(roadCrossingAt(named, here, prev, next), { name: 'Hunter Mill Road', signal: false });
	const unnamed = { tags: {}, roads: [road({ highway: 'residential' }, [north, south])] };
	assert.deepEqual(roadCrossingAt(unnamed, here, prev, next), { name: null, signal: false });
	assert.equal(roadCrossingAt(undefined, here, prev, next), null);
});

test('one road split into two ways at the crossing is still one road crossed', () => {
	const entry = {
		tags: {},
		roads: [road({ highway: 'tertiary', name: 'Maple Avenue' }, [north], 60), road({ highway: 'tertiary', name: 'Maple Avenue' }, [south], 61)],
	};
	assert.deepEqual(roadCrossingAt(entry, here, prev, next), { name: 'Maple Avenue', signal: false });
});

test('a road that ends at the trail, or lies on one side of it, is not crossed', () => {
	assert.equal(roadCrossingAt({ tags: {}, roads: [road({ highway: 'residential', name: 'Dead End' }, [north])] }, here, prev, next), null);
	const sameSide = { node: 23, lat: 0.0003, lon: 0.0007 };
	assert.equal(roadCrossingAt({ tags: {}, roads: [road({ highway: 'residential' }, [north, sameSide])] }, here, prev, next), null);
});

test('a road the course turns onto or follows is not crossed', () => {
	const turnOnto = { tags: {}, roads: [road({ highway: 'service', name: 'Tour Road' }, [north, { node: 3, lat: 0, lon: 0.001 }])] };
	assert.equal(roadCrossingAt(turnOnto, here, prev, next), null);
	// Along Tour Road, the course crosses Oak Street at its junction.
	const along = {
		tags: {},
		roads: [
			road({ highway: 'service', name: 'Tour Road' }, [{ node: 1, lat: 0, lon: 0 }, { node: 3, lat: 0, lon: 0.001 }], 70),
			road({ highway: 'residential', name: 'Oak Street' }, [north, south], 71),
		],
	};
	assert.deepEqual(roadCrossingAt(along, here, prev, next), { name: 'Oak Street', signal: false });
});

test('a bridge, a tunnel, an unnamed service road or a closed road is not crossed', () => {
	for (const tags of /** @type {Record<string, string>[]} */ ([
		{ highway: 'primary', name: 'Route 7', bridge: 'yes' },
		{ highway: 'primary', name: 'Route 7', tunnel: 'yes' },
		{ highway: 'service' },
		{ highway: 'service', service: 'parking_aisle', name: 'Lot' },
		{ highway: 'unclassified', motor_vehicle: 'no' },
	])) {
		assert.equal(roadCrossingAt({ tags: {}, roads: [road(tags, [north, south])] }, here, prev, next), null, JSON.stringify(tags));
	}
});

test('a signal on the crossing node, or within ROAD_SIGNAL_NEAR_M along the road, is a signal', () => {
	const tags = { highway: 'secondary', name: 'Hunter Mill Road' };
	const onNode = { tags: { highway: 'crossing', crossing: 'traffic_signals' }, roads: [road(tags, [north, south])] };
	assert.equal(roadCrossingAt(onNode, here, prev, next)?.signal, true);
	const near = { tags: {}, roads: [road(tags, [{ ...north, signal_m: ROAD_SIGNAL_NEAR_M }, south])] };
	assert.equal(roadCrossingAt(near, here, prev, next)?.signal, true);
	const far = { tags: {}, roads: [road(tags, [{ ...north, signal_m: ROAD_SIGNAL_NEAR_M + 3 }, south])] };
	assert.equal(roadCrossingAt(far, here, prev, next)?.signal, false);
	const marked = { tags: { highway: 'crossing', crossing: 'marked' }, roads: [road(tags, [north, south])] };
	assert.equal(roadCrossingAt(marked, here, prev, next)?.signal, false);
});

test('where two roads meet at the crossing, the named, bigger one is the name', () => {
	const entry = {
		tags: {},
		roads: [
			road({ highway: 'residential' }, [north, south], 80),
			road({ highway: 'residential', name: 'Elm Street' }, [north, south], 81),
			road({ highway: 'secondary', name: 'Church Street' }, [north, south], 82),
		],
	};
	assert.equal(roadCrossingAt(entry, here, prev, next)?.name, 'Church Street');
});

// Overpass: a north-south road (way 500) through course node 2, with a signal 11 m north of it.
/** @param {unknown[]} [extra] */
const overpass = (extra = []) => ({
	elements: [
		{ type: 'node', id: 2, lat: 0, lon: 0.0005, tags: { highway: 'crossing', crossing: 'marked', name: 'dropped' } },
		{ type: 'node', id: 21, lat: 0.0001, lon: 0.0005, tags: { highway: 'traffic_signals' } },
		{ type: 'node', id: 22, lat: -0.0003, lon: 0.0005 },
		{ type: 'node', id: 23, lat: -0.0006, lon: 0.0005 },
		{ type: 'way', id: 500, nodes: [21, 2, 22, 23], tags: { highway: 'secondary', name: 'Hunter Mill Road', lanes: '2', maxspeed: '35 mph' } },
		{ type: 'way', id: 501, nodes: [22, 23], tags: { highway: 'footway' } },
		...extra,
	],
});

test('parseRoadCrossings keeps each course node a road passes through, its arms and the signal distance', () => {
	assert.deepEqual(parseRoadCrossings(overpass(), [1, 2, 3]), {
		2: {
			tags: { crossing: 'marked', highway: 'crossing' },
			roads: [
				{
					id: 500,
					tags: { highway: 'secondary', name: 'Hunter Mill Road' },
					arms: [
						{ node: 21, lat: 0.0001, lon: 0.0005, signal_m: 11 },
						{ node: 22, lat: -0.0003, lon: 0.0005 },
					],
				},
			],
		},
	});
	assert.deepEqual(parseRoadCrossings(overpass(), [1, 3]), {});
});

test('parseRoadCrossings walks a closed road both ways round', () => {
	const ring = {
		elements: [
			{ type: 'node', id: 2, lat: 0, lon: 0 },
			{ type: 'node', id: 31, lat: 0.001, lon: 0 },
			{ type: 'node', id: 32, lat: 0.001, lon: 0.001 },
			{ type: 'way', id: 600, nodes: [2, 31, 32, 2], tags: { highway: 'residential', junction: 'roundabout' } },
		],
	};
	const arms = parseRoadCrossings(ring, [2])['2'].roads[0].arms.map((a) => a.node);
	assert.deepEqual(arms, [32, 31]);
});

test('parseRoadCrossings refuses a response that is not Overpass data', () => {
	assert.throws(() => parseRoadCrossings({}, [2]), /no elements array/);
	assert.throws(() => parseRoadCrossings({ elements: [{ type: 'node', id: -1, lat: 0, lon: 0 }] }, [2]), /positive integer/);
	assert.throws(() => parseRoadCrossings({ elements: [{ type: 'node', id: 1, lat: 91, lon: 0 }] }, [2]), /valid coordinate/);
	assert.throws(() => parseRoadCrossings({ elements: [{ type: 'relation', id: 1 }] }, [2]), /unexpected/);
	assert.throws(
		() => parseRoadCrossings({ elements: [{ type: 'way', id: 9, nodes: [2, 99], tags: { highway: 'residential' } }] }, [2]),
		/omits node/,
	);
	assert.throws(
		() => parseRoadCrossings(overpass([{ type: 'way', id: 9, nodes: [2, 22], tags: { highway: 'x'.repeat(300) } }]), [2]),
		/string pair/,
	);
});
