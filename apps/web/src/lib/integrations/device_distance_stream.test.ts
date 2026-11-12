// Embedded bests prefer the file's own per-point distance stream (FIT
// `record.distance`) over re-estimating from positions, and fall back to the
// estimator when the stream cannot stand in for it (issue #1090 item 7a).
// Lockstep with the Deno twin in
// apps/backend/supabase/functions/_shared/strava_device_distance.test.ts.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { TrackPoint } from '../types';
import { computeEmbeddedBests, deviceCumulativeMetres, parseFitBuffer } from './garmin-fit';

const M_PER_DEG = 6371000 * (Math.PI / 180);
const SEMI = 2 ** 31 / 180;

function evenTrack(segments: number, stepM: number, stepS: number): TrackPoint[] {
	const startMs = Date.parse('2026-01-01T09:00:00Z');
	return Array.from({ length: segments + 1 }, (_, i) => ({
		lat: 0,
		lng: (i * stepM) / M_PER_DEG,
		ts: new Date(startMs + i * stepS * 1000).toISOString(),
	}));
}

test('deviceCumulativeMetres — a monotonic stream is rebased to the first point', () => {
	assert.deepEqual(deviceCumulativeMetres([12, 12, 40.5, 100], 4), [0, 0, 28.5, 88]);
});

test('deviceCumulativeMetres — refuses every stream that cannot stand in for the estimator', () => {
	assert.equal(deviceCumulativeMetres(null, 3), null, 'absent');
	assert.equal(deviceCumulativeMetres(undefined, 3), null, 'absent');
	assert.equal(deviceCumulativeMetres([0, 10], 3), null, 'length mismatch');
	assert.equal(deviceCumulativeMetres([0], 1), null, 'one point');
	assert.equal(deviceCumulativeMetres([0, NaN, 20], 3), null, 'NaN sample');
	assert.equal(deviceCumulativeMetres([0, Infinity, 20], 3), null, 'infinite sample');
	assert.equal(deviceCumulativeMetres([0, '10', 20], 3), null, 'non-number sample');
	assert.equal(deviceCumulativeMetres([0, null, 20], 3), null, 'missing sample');
	assert.equal(deviceCumulativeMetres([-1, 0, 20], 3), null, 'negative sample');
	assert.equal(deviceCumulativeMetres([0, 30, 20], 3), null, 'non-monotonic');
	assert.equal(deviceCumulativeMetres([0, 0, 0], 3), null, 'all zero');
	assert.equal(deviceCumulativeMetres([55, 55, 55], 3), null, 'no distance gained');
});

test('computeEmbeddedBests — measures on a valid device stream, not the positions', () => {
	// Positions: 6 km at 5:00/km (100 m per 30 s). Device stream: 200 m per
	// 30 s, i.e. 12 km. The estimator alone would find a ~1500 s 5k and no
	// 10k; the stream gives an exact 750 s 5k and a 1500 s 10k.
	const track = evenTrack(60, 100, 30);
	const stream = track.map((_, i) => i * 200);
	const bests = computeEmbeddedBests(track, 'run', stream);
	assert.equal(bests.fastest_5k_s, 750);
	assert.equal(bests.fastest_10k_s, 1500);
});

test('computeEmbeddedBests — an invalid device stream falls back to the estimator', () => {
	const track = evenTrack(60, 100, 30);
	const estimated = computeEmbeddedBests(track, 'run');
	const broken = track.map((_, i) => (i === 30 ? NaN : i * 200));
	assert.deepEqual(computeEmbeddedBests(track, 'run', broken), estimated);
	const backwards = track.map((_, i) => (i === 30 ? 0 : i * 200));
	assert.deepEqual(computeEmbeddedBests(track, 'run', backwards), estimated);
	assert.deepEqual(computeEmbeddedBests(track, 'run', track.map(() => 0)), estimated);
	assert.deepEqual(computeEmbeddedBests(track, 'run', [0, 200]), estimated);
	assert.equal(estimated.fastest_10k_s, undefined);
});

function crc16(buf: Uint8Array): number {
	const table = [
		0x0000, 0xcc01, 0xd801, 0x1400, 0xf001, 0x3c00, 0x2800, 0xe401, 0xa001, 0x6c00, 0x7800,
		0xb401, 0x5000, 0x9c01, 0x8801, 0x4400,
	];
	let crc = 0;
	for (let i = 0; i < buf.length; i++) {
		const byte = buf[i];
		let tmp = table[crc & 0xf];
		crc = (crc >> 4) & 0x0fff;
		crc = crc ^ tmp ^ table[byte & 0xf];
		tmp = table[crc & 0xf];
		crc = (crc >> 4) & 0x0fff;
		crc = crc ^ tmp ^ table[(byte >> 4) & 0xf];
	}
	return crc;
}

/// A minimal outdoor running FIT: three positioned records, optionally each
/// carrying `distance` (field 5, uint32, scale 100), plus a session.
function buildRunFit(distancesM: number[] | null): ArrayBuffer {
	const chunks: Buffer[] = [];
	function defMsg(localNum: number, globalNum: number, fields: [number, number, number][]) {
		const def = Buffer.alloc(6 + fields.length * 3);
		def[0] = 0x40 | localNum;
		def.writeUInt16LE(globalNum, 3);
		def[5] = fields.length;
		fields.forEach(([num, size, base], i) => {
			def[6 + i * 3] = num;
			def[6 + i * 3 + 1] = size;
			def[6 + i * 3 + 2] = base;
		});
		chunks.push(def);
	}
	const t0 = 1000000000;

	defMsg(0, 0, [[0, 1, 0x00], [4, 4, 0x86], [3, 4, 0x8c]]);
	{
		const d = Buffer.alloc(1 + 1 + 4 + 4);
		d[0] = 0;
		d[1] = 4;
		d.writeUInt32LE(t0, 2);
		d.writeUInt32LE(4242, 6);
		chunks.push(d);
	}

	const recFields: [number, number, number][] = [
		[253, 4, 0x86],
		[0, 4, 0x85],
		[1, 4, 0x85],
	];
	if (distancesM) recFields.push([5, 4, 0x86]);
	defMsg(1, 20, recFields);
	for (let i = 0; i < 3; i++) {
		const d = Buffer.alloc(1 + 12 + (distancesM ? 4 : 0));
		d[0] = 1;
		d.writeUInt32LE(t0 + i * 60, 1);
		d.writeInt32LE(Math.round(51.5 * SEMI), 5);
		d.writeInt32LE(Math.round((-0.12 + i * 0.002) * SEMI), 9);
		if (distancesM) d.writeUInt32LE(Math.round(distancesM[i] * 100), 13);
		chunks.push(d);
	}

	defMsg(2, 18, [[2, 4, 0x86], [5, 1, 0x00], [7, 4, 0x86], [9, 4, 0x86]]);
	{
		const d = Buffer.alloc(1 + 4 + 1 + 4 + 4);
		d[0] = 2;
		d.writeUInt32LE(t0, 1);
		d[5] = 1;
		d.writeUInt32LE(120 * 1000, 6);
		d.writeUInt32LE(301 * 100, 10);
		chunks.push(d);
	}

	const body = Buffer.concat(chunks);
	const header = Buffer.alloc(14);
	header[0] = 14;
	header[1] = 0x10;
	header.writeUInt16LE(2140, 2);
	header.writeUInt32LE(body.length, 4);
	header.write('.FIT', 8, 'ascii');
	header.writeUInt16LE(crc16(header.subarray(0, 12)), 12);
	const full = Buffer.concat([header, body]);
	const crc = Buffer.alloc(2);
	crc.writeUInt16LE(crc16(full), 0);
	const out = Buffer.concat([full, crc]);
	return out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength) as ArrayBuffer;
}

test('parseFitBuffer — exposes record.distance aligned with the track', async () => {
	const parsed = await parseFitBuffer(buildRunFit([0, 150.5, 301]));
	assert.ok(parsed);
	assert.equal(parsed.track.length, 3);
	assert.deepEqual(parsed.distance_stream, [0, 150.5, 301]);
	assert.deepEqual(deviceCumulativeMetres(parsed.distance_stream, parsed.track.length), [
		0, 150.5, 301,
	]);
});

test('parseFitBuffer — a file whose records carry no distance has no stream', async () => {
	const parsed = await parseFitBuffer(buildRunFit(null));
	assert.ok(parsed);
	assert.equal(parsed.track.length, 3);
	assert.equal(parsed.distance_stream, null);
});
