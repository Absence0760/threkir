import { test } from 'node:test';
import assert from 'node:assert/strict';
import { insertPing, pingTimeMs, traceLineCoords, type TracePing } from './live_trace';

function ping(atMs: number | null, lat: number, extra: Partial<TracePing> = {}): TracePing {
	return {
		lat,
		lng: 0,
		distanceM: lat * 10,
		elapsedS: lat,
		bpm: null,
		atMs,
		coarse: false,
		weakGps: false,
		...extra,
	};
}

test('insertPing: in-order arrivals each become the newest', () => {
	const pings: TracePing[] = [];
	assert.equal(insertPing(pings, ping(1000, 1)), 'newest');
	assert.equal(insertPing(pings, ping(2000, 2)), 'newest');
	assert.deepEqual(
		pings.map((p) => p.lat),
		[1, 2],
	);
});

test('insertPing: a late arrival lands in time order, not at the end', () => {
	const pings: TracePing[] = [];
	insertPing(pings, ping(1000, 1));
	insertPing(pings, ping(3000, 3));
	assert.equal(insertPing(pings, ping(2000, 2)), 'older');
	assert.deepEqual(
		pings.map((p) => p.lat),
		[1, 2, 3],
	);
});

test('insertPing: the backlog overlapping the stream is not drawn twice', () => {
	const pings: TracePing[] = [];
	insertPing(pings, ping(2000, 2));
	insertPing(pings, ping(3000, 3));
	for (const p of [ping(1000, 1), ping(2000, 2), ping(3000, 3)]) insertPing(pings, p);
	assert.deepEqual(
		pings.map((p) => p.lat),
		[1, 2, 3],
	);
});

test('insertPing: a duplicate reports itself and changes nothing', () => {
	const pings: TracePing[] = [];
	insertPing(pings, ping(1000, 1));
	assert.equal(insertPing(pings, ping(1000, 1)), 'duplicate');
	assert.equal(pings.length, 1);
});

test('insertPing: two different pings sharing a clock are both kept, in arrival order', () => {
	const pings: TracePing[] = [];
	insertPing(pings, ping(1000, 1));
	assert.equal(insertPing(pings, ping(1000, 2)), 'newest');
	assert.deepEqual(
		pings.map((p) => p.lat),
		[1, 2],
	);
});

test('insertPing: a ping without a clock goes last, and a replay of it is dropped', () => {
	const pings: TracePing[] = [];
	insertPing(pings, ping(5000, 1));
	assert.equal(insertPing(pings, ping(null, 2)), 'newest');
	assert.equal(insertPing(pings, ping(null, 2)), 'duplicate');
	assert.equal(insertPing(pings, ping(null, 3)), 'newest');
	assert.deepEqual(
		pings.map((p) => p.lat),
		[1, 2, 3],
	);
});

test('insertPing: an old ping arriving after the newest does not take its place', () => {
	const pings: TracePing[] = [];
	insertPing(pings, ping(9000, 9));
	assert.equal(insertPing(pings, ping(1000, 1)), 'older');
	assert.equal(pings[pings.length - 1].lat, 9);
});

test('traceLineCoords: only precise fixes join the line', () => {
	const pings: TracePing[] = [];
	insertPing(pings, ping(1000, 1));
	insertPing(pings, ping(2000, 2, { weakGps: true }));
	insertPing(pings, ping(3000, 3, { coarse: true }));
	insertPing(pings, ping(4000, 4));
	assert.deepEqual(traceLineCoords(pings), [
		[0, 1],
		[0, 4],
	]);
});

test('pingTimeMs: the hub clock wins, and zero is no clock', () => {
	assert.equal(pingTimeMs('2026-11-06T10:00:00Z', 1234), 1234);
	assert.equal(pingTimeMs('2026-11-06T10:00:00Z', 0), Date.parse('2026-11-06T10:00:00Z'));
	assert.equal(pingTimeMs(null, 0), null);
	assert.equal(pingTimeMs('not a date', null), null);
	assert.equal(pingTimeMs(undefined, undefined), null);
	assert.equal(pingTimeMs('2026-11-06 10:00:00.5+00', null), Date.parse('2026-11-06T10:00:00.5Z'));
	for (const bad of ['2026-11-06', '2026-11-06T10:00:00', 'Nov 6 2026 10:00 UTC', '2026-13-40T10:00:00Z']) {
		assert.equal(pingTimeMs(bad, null), null, bad);
	}
});
