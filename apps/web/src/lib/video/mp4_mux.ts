/// A minimal MP4 (ISO BMFF) writer for one H.264 video track, which is all a
/// video export produces. WebCodecs hands back AVCC-framed access units and
/// the `avcC` record; this lays them out as `ftyp`, then `moov`, then one
/// `mdat` chunk, with `moov` first so a player or an upload can start before
/// the end of the file. Pure bytes in, bytes out, so the box layout is pinned
/// by unit tests rather than trusted to a player.
///
/// Out of scope by design: audio, fragmented MP4, and files over 4 GiB (32-bit
/// box sizes and chunk offsets). A 20 s 8 Mbit/s flyover is about 20 MB.

export interface Mp4Sample {
	data: Uint8Array;
	/// Presentation time in microseconds.
	timestampUs: number;
	durationUs: number;
	keyframe: boolean;
}

export interface Mp4Track {
	width: number;
	height: number;
	/// The `AVCDecoderConfigurationRecord` (WebCodecs' `decoderConfig.description`).
	avcC: Uint8Array;
	/// In decode order, as the encoder emitted them.
	samples: readonly Mp4Sample[];
}

/// 90 kHz, the MPEG video clock: every 30 fps frame time is a whole tick.
export const MP4_TIMESCALE = 90_000;
const MOVIE_TIMESCALE = 1000;

const enc = new TextEncoder();

class Writer {
	private chunks: Uint8Array[] = [];
	length = 0;

	bytes(b: Uint8Array): this {
		this.chunks.push(b);
		this.length += b.length;
		return this;
	}

	u8(v: number): this {
		return this.bytes(Uint8Array.of(v & 0xff));
	}

	u16(v: number): this {
		return this.bytes(Uint8Array.of((v >>> 8) & 0xff, v & 0xff));
	}

	u32(v: number): this {
		const b = new Uint8Array(4);
		new DataView(b.buffer).setUint32(0, v >>> 0);
		return this.bytes(b);
	}

	i32(v: number): this {
		const b = new Uint8Array(4);
		new DataView(b.buffer).setInt32(0, v | 0);
		return this.bytes(b);
	}

	ascii(s: string): this {
		return this.bytes(enc.encode(s));
	}

	zeros(n: number): this {
		return this.bytes(new Uint8Array(n));
	}

	finish(): Uint8Array {
		const out = new Uint8Array(this.length);
		let at = 0;
		for (const c of this.chunks) {
			out.set(c, at);
			at += c.length;
		}
		return out;
	}
}

function box(type: string, ...body: Uint8Array[]): Uint8Array {
	const w = new Writer();
	const size = 8 + body.reduce((n, b) => n + b.length, 0);
	w.u32(size).ascii(type);
	for (const b of body) w.bytes(b);
	return w.finish();
}

function fullBox(type: string, version: number, flags: number, body: Writer): Uint8Array {
	const head = new Writer().u8(version).u8(flags >>> 16).u16(flags & 0xffff);
	return box(type, head.finish(), body.finish());
}

const MATRIX = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000];

function matrix(w: Writer): Writer {
	for (const v of MATRIX) w.u32(v);
	return w;
}

function ticks(us: number): number {
	return Math.round((us * MP4_TIMESCALE) / 1_000_000);
}

interface Timing {
	durations: number[];
	offsets: number[];
	total: number;
}

/// Decode times are the presentation times in sorted order, so a stream with
/// no reordering gets offsets of zero and no `ctts` box at all; one with
/// B-frames gets signed offsets in a version-1 `ctts`.
function timing(samples: readonly Mp4Sample[]): Timing {
	const pts = samples.map((s) => ticks(s.timestampUs));
	const base = pts.length > 0 ? Math.min(...pts) : 0;
	const rel = pts.map((p) => p - base);
	const dts = [...rel].sort((a, b) => a - b);
	const durations = dts.map((d, i) =>
		i + 1 < dts.length ? dts[i + 1] - d : Math.max(1, ticks(samples[samples.length - 1].durationUs)),
	);
	const offsets = rel.map((p, i) => p - dts[i]);
	const total = durations.reduce((a, b) => a + b, 0);
	return { durations, offsets, total };
}

function runLength(values: readonly number[]): [number, number][] {
	const runs: [number, number][] = [];
	for (const v of values) {
		const last = runs[runs.length - 1];
		if (last && last[1] === v) last[0]++;
		else runs.push([1, v]);
	}
	return runs;
}

function avc1(track: Mp4Track): Uint8Array {
	const w = new Writer()
		.zeros(6)
		.u16(1)
		.u16(0)
		.u16(0)
		.zeros(12)
		.u16(track.width)
		.u16(track.height)
		.u32(0x00480000)
		.u32(0x00480000)
		.u32(0)
		.u16(1)
		.zeros(32)
		.u16(0x0018)
		.u16(0xffff);
	return box('avc1', w.finish(), box('avcC', track.avcC));
}

function stbl(track: Mp4Track, t: Timing, chunkOffset: number): Uint8Array {
	const n = track.samples.length;
	const stsd = fullBox('stsd', 0, 0, new Writer().u32(1).bytes(avc1(track)));

	const sttsRuns = runLength(t.durations);
	const stts = new Writer().u32(sttsRuns.length);
	for (const [count, delta] of sttsRuns) stts.u32(count).u32(delta);

	const boxes = [stsd, fullBox('stts', 0, 0, stts)];

	if (t.offsets.some((o) => o !== 0)) {
		const cttsRuns = runLength(t.offsets);
		const ctts = new Writer().u32(cttsRuns.length);
		for (const [count, offset] of cttsRuns) ctts.u32(count).i32(offset);
		boxes.push(fullBox('ctts', 1, 0, ctts));
	}

	const keys = track.samples.flatMap((s, i) => (s.keyframe ? [i + 1] : []));
	if (keys.length < n) {
		const stss = new Writer().u32(keys.length);
		for (const k of keys) stss.u32(k);
		boxes.push(fullBox('stss', 0, 0, stss));
	}

	const stsc = new Writer().u32(n > 0 ? 1 : 0);
	if (n > 0) stsc.u32(1).u32(n).u32(1);
	boxes.push(fullBox('stsc', 0, 0, stsc));

	const stsz = new Writer().u32(0).u32(n);
	for (const s of track.samples) stsz.u32(s.data.length);
	boxes.push(fullBox('stsz', 0, 0, stsz));
	boxes.push(fullBox('stco', 0, 0, new Writer().u32(1).u32(chunkOffset)));
	return box('stbl', ...boxes);
}

function moov(track: Mp4Track, t: Timing, chunkOffset: number): Uint8Array {
	const movieDuration = Math.round((t.total * MOVIE_TIMESCALE) / MP4_TIMESCALE);
	const mvhd = fullBox(
		'mvhd',
		0,
		0,
		matrix(
			new Writer()
				.u32(0)
				.u32(0)
				.u32(MOVIE_TIMESCALE)
				.u32(movieDuration)
				.u32(0x00010000)
				.u16(0x0100)
				.zeros(10),
		)
			.zeros(24)
			.u32(2),
	);
	const tkhd = fullBox(
		'tkhd',
		0,
		0x000003,
		matrix(new Writer().u32(0).u32(0).u32(1).u32(0).u32(movieDuration).zeros(8).u16(0).u16(0).u16(0).u16(0))
			.u32(track.width << 16)
			.u32(track.height << 16),
	);
	const mdhd = fullBox(
		'mdhd',
		0,
		0,
		new Writer().u32(0).u32(0).u32(MP4_TIMESCALE).u32(t.total).u16(0x55c4).u16(0),
	);
	const hdlr = fullBox(
		'hdlr',
		0,
		0,
		new Writer().u32(0).ascii('vide').zeros(12).ascii('VideoHandler').u8(0),
	);
	const vmhd = fullBox('vmhd', 0, 1, new Writer().u16(0).u16(0).u16(0).u16(0));
	const dref = fullBox('dref', 0, 0, new Writer().u32(1).bytes(fullBox('url ', 0, 1, new Writer())));
	const minf = box('minf', vmhd, box('dinf', dref), stbl(track, t, chunkOffset));
	const mdia = box('mdia', mdhd, hdlr, minf);
	return box('moov', mvhd, box('trak', tkhd, mdia));
}

export function muxMp4(track: Mp4Track): Uint8Array {
	const ftyp = box(
		'ftyp',
		new Writer().ascii('isom').u32(0x200).ascii('isom').ascii('iso2').ascii('avc1').ascii('mp41').finish(),
	);
	const t = timing(track.samples);
	// The chunk offset is written inside moov, and moov's size does not depend
	// on the offset's value, so measure once with a placeholder.
	const moovSize = moov(track, t, 0).length;
	const mdatHeader = 8;
	const offset = ftyp.length + moovSize + mdatHeader;
	const payload = track.samples.reduce((n, s) => n + s.data.length, 0);
	const mdat = new Writer().u32(mdatHeader + payload).ascii('mdat');
	for (const s of track.samples) mdat.bytes(s.data);
	const out = new Writer().bytes(ftyp).bytes(moov(track, t, offset)).bytes(mdat.finish());
	return out.finish();
}
