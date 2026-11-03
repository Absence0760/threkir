import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { muxMp4, MP4_TIMESCALE, type Mp4Sample } from './mp4_mux.ts';

interface Box {
	type: string;
	start: number;
	size: number;
	body: Uint8Array;
}

const CONTAINERS = new Set(['moov', 'trak', 'mdia', 'minf', 'dinf', 'stbl']);

function boxes(bytes: Uint8Array, start = 0, end = bytes.length): Box[] {
	const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
	const out: Box[] = [];
	let at = start;
	while (at < end) {
		const size = dv.getUint32(at);
		assert.ok(size >= 8 && at + size <= end, `box at ${at} has size ${size}`);
		const type = String.fromCharCode(...bytes.subarray(at + 4, at + 8));
		out.push({ type, start: at, size, body: bytes.subarray(at + 8, at + size) });
		at += size;
	}
	assert.equal(at, end, 'boxes tile their parent exactly');
	return out;
}

function find(bytes: Uint8Array, path: string[]): Box {
	let level = boxes(bytes);
	let hit: Box | undefined;
	for (const type of path) {
		hit = level.find((b) => b.type === type);
		assert.ok(hit, `missing ${path.join('/')}`);
		if (CONTAINERS.has(type)) level = boxes(bytes, hit.start + 8, hit.start + hit.size);
		else if (type === 'stsd') level = boxes(bytes, hit.start + 16, hit.start + hit.size);
	}
	return hit as Box;
}

function u32s(b: Uint8Array, from: number, count: number): number[] {
	const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
	return Array.from({ length: count }, (_, i) => dv.getUint32(from + i * 4));
}

const AVCC = Uint8Array.of(1, 0x64, 0, 0x28, 0xff, 0xe1, 0, 0);

function samples(pts: number[], keys: number[] = [0]): Mp4Sample[] {
	return pts.map((p, i) => ({
		data: Uint8Array.from({ length: 10 + i }, () => i + 1),
		timestampUs: p,
		durationUs: 33_333,
		keyframe: keys.includes(i),
	}));
}

test('ftyp, then moov, then one mdat, tiling the whole file', () => {
	const file = muxMp4({ width: 1080, height: 1920, avcC: AVCC, samples: samples([0, 33_333, 66_667]) });
	assert.deepEqual(
		boxes(file).map((b) => b.type),
		['ftyp', 'moov', 'mdat'],
	);
	assert.equal(String.fromCharCode(...file.subarray(8, 12)), 'isom');
});

test('the chunk offset points at the first sample and sizes walk the rest', () => {
	const s = samples([0, 33_333, 66_667]);
	const file = muxMp4({ width: 1080, height: 1920, avcC: AVCC, samples: s });
	const stco = find(file, ['moov', 'trak', 'mdia', 'minf', 'stbl', 'stco']);
	const [count, offset] = u32s(stco.body, 4, 2);
	assert.equal(count, 1);
	const stsz = find(file, ['moov', 'trak', 'mdia', 'minf', 'stbl', 'stsz']);
	const [fixed, n, ...sizes] = u32s(stsz.body, 4, 5);
	assert.deepEqual([fixed, n, sizes], [0, 3, [10, 11, 12]]);
	let at = offset;
	for (const [i, sample] of s.entries()) {
		assert.deepEqual(file.subarray(at, at + sample.data.length), sample.data, `sample ${i}`);
		at += sample.data.length;
	}
	assert.equal(at, file.length);
});

test('frame durations land in stts on the 90 kHz clock, and the movie is as long as the frames', () => {
	const file = muxMp4({ width: 1080, height: 1920, avcC: AVCC, samples: samples([0, 33_333, 66_667, 100_000]) });
	const stts = find(file, ['moov', 'trak', 'mdia', 'minf', 'stbl', 'stts']);
	assert.deepEqual(u32s(stts.body, 4, 3), [1, 4, 3000]);
	const gap = muxMp4({ width: 8, height: 8, avcC: AVCC, samples: samples([0, 33_333, 100_000]) });
	const gapStts = find(gap, ['moov', 'trak', 'mdia', 'minf', 'stbl', 'stts']);
	assert.deepEqual(u32s(gapStts.body, 4, 7), [3, 1, 3000, 1, 6000, 1, 3000]);
	const mdhd = find(file, ['moov', 'trak', 'mdia', 'mdhd']);
	const [, , timescale, duration] = u32s(mdhd.body, 4, 4);
	assert.equal(timescale, MP4_TIMESCALE);
	assert.equal(duration, 12_000);
	const mvhd = find(file, ['moov', 'mvhd']);
	assert.deepEqual(u32s(mvhd.body, 12, 2), [1000, 133]);
});

test('only non-key samples get an stss entry list; an all-key stream has none', () => {
	const mixed = muxMp4({ width: 8, height: 8, avcC: AVCC, samples: samples([0, 33_333, 66_667], [0, 2]) });
	const stss = find(mixed, ['moov', 'trak', 'mdia', 'minf', 'stbl', 'stss']);
	assert.deepEqual(u32s(stss.body, 4, 3), [2, 1, 3]);
	const allKey = muxMp4({ width: 8, height: 8, avcC: AVCC, samples: samples([0, 33_333], [0, 1]) });
	const stbl = find(allKey, ['moov', 'trak', 'mdia', 'minf', 'stbl']);
	assert.ok(!boxes(allKey, stbl.start + 8, stbl.start + stbl.size).some((b) => b.type === 'stss'));
});

test('in-order frames need no ctts; reordered ones get signed v1 offsets', () => {
	const ordered = muxMp4({ width: 8, height: 8, avcC: AVCC, samples: samples([0, 33_333, 66_667]) });
	const stbl = find(ordered, ['moov', 'trak', 'mdia', 'minf', 'stbl']);
	assert.ok(!boxes(ordered, stbl.start + 8, stbl.start + stbl.size).some((b) => b.type === 'ctts'));

	const reordered = muxMp4({
		width: 8,
		height: 8,
		avcC: AVCC,
		samples: samples([0, 100_000, 33_333, 66_667]),
	});
	const ctts = find(reordered, ['moov', 'trak', 'mdia', 'minf', 'stbl', 'ctts']);
	assert.equal(ctts.body[0], 1);
	const dv = new DataView(ctts.body.buffer, ctts.body.byteOffset, ctts.body.byteLength);
	const runs = dv.getUint32(4);
	const entries = Array.from({ length: runs }, (_, i) => [dv.getUint32(8 + i * 8), dv.getInt32(12 + i * 8)]);
	assert.deepEqual(entries, [
		[1, 0],
		[1, 6000],
		[2, -3000],
	]);
});

test('the sample entry is avc1 at the frame size, carrying the encoder avcC verbatim', () => {
	const file = muxMp4({ width: 1080, height: 1920, avcC: AVCC, samples: samples([0]) });
	const avc1 = find(file, ['moov', 'trak', 'mdia', 'minf', 'stbl', 'stsd', 'avc1']);
	const dv = new DataView(avc1.body.buffer, avc1.body.byteOffset, avc1.body.byteLength);
	assert.deepEqual([dv.getUint16(24), dv.getUint16(26)], [1080, 1920]);
	const avcC = boxes(file, avc1.start + 8 + 78, avc1.start + avc1.size)[0];
	assert.equal(avcC.type, 'avcC');
	assert.deepEqual(avcC.body, AVCC);
	const tkhd = find(file, ['moov', 'trak', 'tkhd']);
	assert.deepEqual(u32s(tkhd.body, 76, 2), [1080 << 16, 1920 << 16]);
});
