import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { parseFitBuffer } from './garmin-fit';

/// Which FIT records become track points. A FIT position is a signed 32-bit
/// count of semicircles, so ANY value decodes to a number in [-180, 180) —
/// including a latitude no place has. The Dart twin
/// (packages/gpx_parser/lib/src/fit_parser.dart) refuses |lat| > 90 "exactly
/// as the XML parsers do"; these pin the web importer to the same contract.

const SEMI = 2 ** 31 / 180;
const T0 = 1_000_000_000;
const FIT_SINT32_INVALID = 0x7fffffff;

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

interface Rec {
	dt: number;
	/** Degrees, or a raw semicircle count via `rawLat`. */
	lat?: number;
	lng?: number;
	rawLat?: number;
	hr?: number;
}

/// Minimal FIT: file_id, one record per `recs` entry (timestamp, lat, lng,
/// heart_rate — a missing field is written as FIT's own invalid sentinel),
/// and a running session.
function buildFit(recs: Rec[]): ArrayBuffer {
	const chunks: Buffer[] = [];
	function def(localNum: number, globalNum: number, fields: [number, number, number][]) {
		const d = Buffer.alloc(6 + fields.length * 3);
		d[0] = 0x40 | localNum;
		d.writeUInt16LE(globalNum, 3);
		d[5] = fields.length;
		fields.forEach(([num, size, base], i) => {
			d[6 + i * 3] = num;
			d[6 + i * 3 + 1] = size;
			d[6 + i * 3 + 2] = base;
		});
		chunks.push(d);
	}

	def(0, 0, [[0, 1, 0x00], [4, 4, 0x86], [3, 4, 0x8c]]);
	{
		const d = Buffer.alloc(10);
		d[0] = 0;
		d[1] = 4;
		d.writeUInt32LE(T0, 2);
		d.writeUInt32LE(4242, 6);
		chunks.push(d);
	}

	def(1, 20, [[253, 4, 0x86], [0, 4, 0x85], [1, 4, 0x85], [3, 1, 0x02]]);
	for (const r of recs) {
		const d = Buffer.alloc(14);
		d[0] = 1;
		d.writeUInt32LE(T0 + r.dt, 1);
		const lat = r.rawLat ?? (r.lat == null ? FIT_SINT32_INVALID : Math.round(r.lat * SEMI));
		const lng = r.lng == null ? FIT_SINT32_INVALID : Math.round(r.lng * SEMI);
		d.writeInt32LE(lat, 5);
		d.writeInt32LE(lng, 9);
		d[13] = r.hr ?? 0xff;
		chunks.push(d);
	}

	def(2, 18, [[2, 4, 0x86], [5, 1, 0x00], [7, 4, 0x86], [9, 4, 0x86]]);
	{
		const d = Buffer.alloc(14);
		d[0] = 2;
		d.writeUInt32LE(T0, 1);
		d[5] = 1;
		d.writeUInt32LE(600 * 1000, 6);
		d.writeUInt32LE(2000 * 100, 10);
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

test('parseFitBuffer — a decoded latitude past the pole is refused, not plotted', async () => {
	const parsed = await parseFitBuffer(
		buildFit([
			{ dt: 0, lat: 51.5, lng: -0.12, hr: 140 },
			{ dt: 1, lat: 120, lng: -0.12, hr: 141 },
			{ dt: 2, lat: -95, lng: -0.12, hr: 142 },
			{ dt: 3, lat: 51.5001, lng: -0.12, hr: 143 },
		]),
	);
	assert.ok(parsed);
	assert.deepEqual(
		parsed.track.map((p) => Math.round(p.lat * 1e4) / 1e4),
		[51.5, 51.5001],
		'only the two real fixes become track points',
	);
	for (const p of parsed.track) {
		assert.ok(Math.abs(p.lat) <= 90 && Math.abs(p.lng) <= 180, JSON.stringify(p));
	}
});

test('parseFitBuffer — the most negative semicircle count, -180 degrees, is a real longitude', async () => {
	const parsed = await parseFitBuffer(
		buildFit([
			{ dt: 0, lat: -16.5, lng: -180 },
			{ dt: 1, lat: -16.5001, lng: 179.9999 },
		]),
	);
	assert.ok(parsed);
	assert.equal(parsed.track.length, 2, 'the antimeridian is not off the globe');
});

test('parseFitBuffer — a position FIT marks invalid makes no track point', async () => {
	const parsed = await parseFitBuffer(
		buildFit([
			{ dt: 0, lat: 51.5, lng: -0.12, hr: 150 },
			{ dt: 1, hr: 151 },
			{ dt: 2, lat: 51.5, hr: 152 },
			{ dt: 3, lat: 51.5002, lng: -0.12, hr: 153 },
		]),
	);
	assert.ok(parsed);
	assert.equal(parsed.track.length, 2, 'a fix needs both halves');
	assert.deepEqual(parsed.track.map((p) => p.bpm), [150, 153]);
});

test('parseFitBuffer — an out-of-range record with valid HR still feeds the HR series on an indoor-shaped file', async () => {
	// Every record's position is unusable, so the file reads as indoor: its
	// HR must survive as the series rather than vanish with the positions.
	const parsed = await parseFitBuffer(
		buildFit([
			{ dt: 0, rawLat: Math.round(100 * SEMI), lng: 10, hr: 120 },
			{ dt: 1, rawLat: Math.round(100 * SEMI), lng: 10, hr: 125 },
		]),
	);
	assert.ok(parsed);
	assert.equal(parsed.track.length, 0);
	assert.deepEqual(parsed.hr_series.map((s) => s.bpm), [120, 125]);
});
