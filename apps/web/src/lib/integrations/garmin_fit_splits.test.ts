import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { parseFitBuffer, withDeviceDistances } from './garmin-fit';
import { computeRealSplits } from '../runs/run_stats';
import type { TrackPoint } from '../types';

const SEMI = 2 ** 31 / 180;
const METRES_PER_MILE = 1609.344;
const M_PER_DEG = 111_320;

function crc16(buf: Uint8Array): number {
	const table = [
		0x0000, 0xcc01, 0xd801, 0x1400, 0xf001, 0x3c00, 0x2800, 0xe401, 0xa001, 0x6c00, 0x7800,
		0xb401, 0x5000, 0x9c01, 0x8801, 0x4400,
	];
	let crc = 0;
	for (const byte of buf) {
		let tmp = table[crc & 0xf];
		crc = (crc >> 4) & 0x0fff;
		crc = crc ^ tmp ^ table[byte & 0xf];
		tmp = table[crc & 0xf];
		crc = (crc >> 4) & 0x0fff;
		crc = crc ^ tmp ^ table[(byte >> 4) & 0xf];
	}
	return crc;
}

type Rec = { t: number; latM: number; lngM: number; distM: number };

/// A FIT activity whose records carry the watch's own `distance` beside
/// positions that disagree with it, the shape of a city-marathon import: the
/// GPS line zig-zags 3 m either side of the road for the first 600 m (a
/// start among tall buildings), then runs true, and the watch keeps
/// recording for 5 minutes after the finish while the runner stands still.
/// The runner holds 3.0 m/s throughout: 333 s/km, 8:56/mi.
function marathonShapedFit(): { buf: ArrayBuffer; totalM: number } {
	const recs: Rec[] = [];
	const stepS = 2;
	const speed = 3;
	const runHops = 617;
	for (let i = 0; i <= runHops; i++) {
		const d = i * stepS * speed;
		const latM = d < 600 ? (i % 2 === 0 ? 3 : -3) : 0;
		recs.push({ t: i * stepS, latM, lngM: d, distM: d });
	}
	const finish = recs[recs.length - 1];
	for (let k = 1; k <= 60; k++) {
		recs.push({ t: finish.t + k * 5, latM: k % 2 === 0 ? 2 : -2, lngM: finish.lngM, distM: finish.distM });
	}
	const totalM = finish.distM;

	const chunks: Buffer[] = [];
	const def = (local: number, global: number, fields: [number, number, number][]) => {
		const b = Buffer.alloc(6 + fields.length * 3);
		b[0] = 0x40 | local;
		b.writeUInt16LE(global, 3);
		b[5] = fields.length;
		fields.forEach(([num, size, base], i) => {
			b[6 + i * 3] = num;
			b[6 + i * 3 + 1] = size;
			b[6 + i * 3 + 2] = base;
		});
		chunks.push(b);
	};
	const t0 = 1_000_000_000;

	def(0, 0, [[0, 1, 0x00], [4, 4, 0x86], [3, 4, 0x8c]]);
	{
		const d = Buffer.alloc(10);
		d[0] = 0;
		d[1] = 4;
		d.writeUInt32LE(t0, 2);
		d.writeUInt32LE(4242, 6);
		chunks.push(d);
	}

	// record: timestamp, position_lat, position_long, distance (u32, /100 m).
	def(1, 20, [[253, 4, 0x86], [0, 4, 0x85], [1, 4, 0x85], [5, 4, 0x86]]);
	for (const r of recs) {
		const d = Buffer.alloc(17);
		d[0] = 1;
		d.writeUInt32LE(t0 + r.t, 1);
		d.writeInt32LE(Math.round((r.latM / M_PER_DEG) * SEMI), 5);
		d.writeInt32LE(Math.round((r.lngM / M_PER_DEG) * SEMI), 9);
		d.writeUInt32LE(Math.round(r.distM * 100), 13);
		chunks.push(d);
	}

	// session: start_time, sport=running, total_elapsed_time, total_timer_time,
	// total_distance.
	def(2, 18, [[2, 4, 0x86], [5, 1, 0x00], [7, 4, 0x86], [8, 4, 0x86], [9, 4, 0x86]]);
	{
		const last = recs[recs.length - 1];
		const d = Buffer.alloc(18);
		d[0] = 2;
		d.writeUInt32LE(t0, 1);
		d[5] = 1;
		d.writeUInt32LE(last.t * 1000, 6);
		d.writeUInt32LE(finish.t * 1000, 10);
		d.writeUInt32LE(Math.round(totalM * 100), 14);
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
	return { buf: out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength) as ArrayBuffer, totalM };
}

test('parseFitBuffer — every track point carries the watch distance as distM, from 0', async () => {
	const { buf, totalM } = marathonShapedFit();
	const parsed = (await parseFitBuffer(buf))!;
	assert.equal(parsed.track.length, 678);
	assert.ok(parsed.track.every((p) => typeof p.distM === 'number'));
	assert.equal(parsed.track[0].distM, 0);
	assert.ok(Math.abs(parsed.track[parsed.track.length - 1].distM! - totalM) < 0.01);
	assert.equal(parsed.distance_m, totalM);
});

test('an imported .fit splits on the watch distance, so mile splits match its mile auto-laps (#1387)', async () => {
	const { buf } = marathonShapedFit();
	const parsed = (await parseFitBuffer(buf))!;
	const splits = computeRealSplits(parsed.track, METRES_PER_MILE, parsed.distance_m);
	assert.deepEqual(
		splits.map((s) => s.distance_m),
		[1609, 1609, 483],
	);
	for (const s of splits) assert.ok(Math.abs(s.pace_s - 333) <= 1, `split ${s.km} pace ${s.pace_s}`);

	// On the positions alone, the zig-zag at the start reaches the first mile
	// early and reads it far faster than the watch's lap.
	const onPositions = computeRealSplits(
		parsed.track.map(({ distM: _d, ...p }) => p),
		METRES_PER_MILE,
		parsed.distance_m,
	);
	assert.ok(onPositions[0].pace_s < 333 - 30, `positions-only first mile ${onPositions[0].pace_s}`);
});

test('an imported .fit tail split excludes the minutes the watch recorded after the finish (#1388)', async () => {
	const { buf } = marathonShapedFit();
	const parsed = (await parseFitBuffer(buf))!;
	const tail = computeRealSplits(parsed.track, METRES_PER_MILE, parsed.distance_m).at(-1)!;
	assert.equal(tail.distance_m, 483);
	// 483 m at 3.0 m/s is 161 s; the 300 s standing after it would read
	// 954 s/km, 25:35/mi.
	assert.ok(Math.abs(tail.pace_s - 333) <= 1, `tail pace ${tail.pace_s}`);
});

test('withDeviceDistances — leaves the track alone when the stream cannot stand in for it', () => {
	const t: TrackPoint[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0, lng: 0.001 },
		{ lat: 0, lng: 0.002 },
	];
	assert.equal(withDeviceDistances(t, null), t);
	assert.equal(withDeviceDistances(t, [0, 100]), t);
	assert.equal(withDeviceDistances(t, [0, Number.NaN, 200]), t);
	assert.equal(withDeviceDistances(t, [0, 120, 110]), t);
	assert.deepEqual(
		withDeviceDistances(t, [50, 150, 260]).map((p) => p.distM),
		[0, 100, 210],
	);
});
