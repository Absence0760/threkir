import test from 'node:test';
import assert from 'node:assert/strict';

import { parseWayFull } from './osm_response.mjs';

/** @param {Record<string, unknown>} [wayOverrides] @param {unknown[]} [extraNodes] */
function body(wayOverrides = {}, extraNodes = []) {
	return {
		version: '0.6',
		elements: [
			{ type: 'node', id: 1, lat: 37.37, lon: -77.57 },
			{ type: 'node', id: 2, lat: 37.38, lon: -77.58 },
			...extraNodes,
			{ type: 'way', id: 10, version: 4, nodes: [1, 2], tags: { highway: 'path', name: 'Beaver Lake Trail' }, ...wayOverrides },
		],
	};
}

test('a well-formed response yields the way and exactly its checked fields', () => {
	const { way, nodes } = parseWayFull(body({ user: 'someone', changeset: 99 }), 10);
	assert.deepEqual(way, { id: 10, version: 4, tags: { highway: 'path', name: 'Beaver Lake Trail' }, nodes: [1, 2] });
	assert.deepEqual(nodes, { 1: { lat: 37.37, lon: -77.57 }, 2: { lat: 37.38, lon: -77.58 } });
});

test('a way with no tags gets an empty tag set, not undefined', () => {
	const { way } = parseWayFull(body({ tags: undefined }), 10);
	assert.deepEqual(way.tags, {});
});

test('a body that is not an OSM response is refused before anything is written', () => {
	for (const bad of [null, 'oops', {}, { elements: 'x' }, { elements: [null] }]) {
		assert.throws(() => parseWayFull(bad, 10));
	}
});

test('the requested way missing from the response is refused', () => {
	assert.throws(() => parseWayFull(body({ id: 11 }), 10), /no way 10/);
});

test('an out-of-range or non-numeric coordinate is refused', () => {
	for (const node of [
		{ type: 'node', id: 3, lat: 91, lon: 0 },
		{ type: 'node', id: 3, lat: 0, lon: -181 },
		{ type: 'node', id: 3, lat: '37.1', lon: 0 },
		{ type: 'node', id: 3, lat: Number.NaN, lon: 0 },
	]) {
		assert.throws(() => parseWayFull(body({}, [node]), 10), /no valid coordinate/);
	}
});

test('ids, versions and node lists must be positive integers', () => {
	assert.throws(() => parseWayFull(body({}, [{ type: 'node', id: -3, lat: 0, lon: 0 }]), 10), /node id/);
	assert.throws(() => parseWayFull(body({ version: '4' }), 10), /version/);
	assert.throws(() => parseWayFull(body({ nodes: [1] }), 10), /node list/);
	assert.throws(() => parseWayFull(body({ nodes: [1, 2.5] }), 10), /node list/);
});

test('a way naming a node the response did not include is refused', () => {
	assert.throws(() => parseWayFull(body({ nodes: [1, 2, 3] }), 10), /omits node\(s\) 3/);
});

test('tags must be short string pairs, the limit OSM itself enforces', () => {
	assert.throws(() => parseWayFull(body({ tags: { name: 7 } }), 10), /string pair/);
	assert.throws(() => parseWayFull(body({ tags: { name: 'x'.repeat(256) } }), 10), /string pair/);
	assert.throws(() => parseWayFull(body({ tags: ['a'] }), 10), /tags is not an object/);
	assert.doesNotThrow(() => parseWayFull(body({ tags: { name: 'x'.repeat(255) } }), 10));
});

test('a __proto__ tag key stays a key and does not replace the prototype', () => {
	const parsed = JSON.parse('{"elements":[{"type":"node","id":1,"lat":0,"lon":0},{"type":"node","id":2,"lat":0,"lon":0},{"type":"way","id":10,"version":1,"nodes":[1,2],"tags":{"__proto__":"x"}}]}');
	const { way } = parseWayFull(parsed, 10);
	assert.equal(Object.getPrototypeOf(way.tags), Object.prototype);
	assert.deepEqual(Object.keys(way.tags), ['__proto__']);
});
