import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
	CODE128_QUIET_ZONE_MODULES,
	barcodeBars,
	code128BModules,
	code128BSymbols,
} from './parkrun_barcode';

// Does the parkrun barcode SCAN? parkrun_barcode.test.ts pins the encoder's
// own steps; this file reads its output back the way a finish-funnel scanner
// does — quiet zones, element widths, the symbol table, the start code, the
// mod-103 check, the STOP pattern and its terminating bar — through a decoder
// that shares nothing with the encoder. Its symbol table is the 11-module
// bar/space column of the Code 128 table (ISO/IEC 15417 Table 1, as
// transcribed on en.wikipedia.org/wiki/Code_128), written as module strings
// rather than the encoder's width digits so the two cannot share a typo.
//
// The vectors in fixtures/parkrun_barcode_vectors.json are asserted here and
// by apps/mobile_android/test/parkrun_barcode_vectors_test.dart, so the two
// encoders cannot drift apart. Before they were committed every vector was
// also decoded by zxing-cpp from a rendered image.

const ISO_15417_TABLE = `
	11011001100 11001101100 11001100110 10010011000 10010001100 10001001100 10011001000 10011000100
	10001100100 11001001000 11001000100 11000100100 10110011100 10011011100 10011001110 10111001100
	10011101100 10011100110 11001110010 11001011100 11001001110 11011100100 11001110100 11101101110
	11101001100 11100101100 11100100110 11101100100 11100110100 11100110010 11011011000 11011000110
	11000110110 10100011000 10001011000 10001000110 10110001000 10001101000 10001100010 11010001000
	11000101000 11000100010 10110111000 10110001110 10001101110 10111011000 10111000110 10001110110
	11101110110 11010001110 11000101110 11011101000 11011100010 11011101110 11101011000 11101000110
	11100010110 11101101000 11101100010 11100011010 11101111010 11001000010 11110001010 10100110000
	10100001100 10010110000 10010000110 10000101100 10000100110 10110010000 10110000100 10011010000
	10011000010 10000110100 10000110010 11000010010 11001010000 11110111010 11000010100 10001111010
	10100111100 10010111100 10010011110 10111100100 10011110100 10011110010 11110100100 11110010100
	11110010010 11011011110 11011110110 11110110110 10101111000 10100011110 10001011110 10111101000
	10111100010 11110101000 11110100010 10111011110 10111101110 11101011110 11110101110 11010000100
	11010010000 11010011100 11000111010
`
	.trim()
	.split(/\s+/);

const VALUE_OF = new Map(ISO_15417_TABLE.map((bits, value) => [bits, value]));
const START_A = 103;
const START_B = 104;
const START_C = 105;
const STOP = 106;

interface Decoded {
	text: string;
	startSet: 'A' | 'B' | 'C';
	/** Every symbol value, START through STOP. */
	symbols: number[];
}

/**
 * A module row (`1` bar, `0` space) read left to right, quiet zones
 * included, decoded the way ISO/IEC 15417 describes. Throws on anything a
 * scanner would refuse.
 */
function decode(row: string, minQuietZone = CODE128_QUIET_ZONE_MODULES): Decoded {
	const first = row.indexOf('1');
	const last = row.lastIndexOf('1');
	if (first < 0) throw new Error('no bars');
	if (first < minQuietZone) throw new Error(`leading quiet zone ${first} < ${minQuietZone}`);
	const trailing = row.length - 1 - last;
	if (trailing < minQuietZone) throw new Error(`trailing quiet zone ${trailing} < ${minQuietZone}`);
	const body = row.slice(first, last + 1);

	// Symbols are 11 modules; the STOP symbol is followed by a 2-module bar.
	if ((body.length - 2) % 11 !== 0) throw new Error(`body of ${body.length} modules is not 11n + 2`);
	if (body.slice(-2) !== '11' || body[body.length - 3] !== '0') {
		throw new Error('missing the 2-module terminating bar');
	}
	const symbols: number[] = [];
	for (let i = 0; i < body.length - 2; i += 11) {
		const bits = body.slice(i, i + 11);
		// Every symbol is bar-first and ends on a space: three bars, three spaces.
		const runs = bits.match(/1+|0+/g) ?? [];
		if (runs.length !== 6 || bits[0] !== '1') throw new Error(`symbol ${i / 11} has ${runs.length} elements`);
		const barModules = runs.filter((_, k) => k % 2 === 0).reduce((s, r) => s + r.length, 0);
		if (barModules % 2 !== 0) throw new Error(`symbol ${i / 11} fails the even-bar parity`);
		const value = VALUE_OF.get(bits);
		if (value === undefined) throw new Error(`symbol ${i / 11} (${bits}) is not in the table`);
		symbols.push(value);
	}
	if (symbols.length < 3) throw new Error('too short');
	if (symbols[symbols.length - 1] !== STOP) throw new Error('does not end in STOP');
	if (symbols.slice(1, -1).some((v) => v >= START_A)) throw new Error('a start or stop code inside the data');

	const start = symbols[0];
	const startSet = start === START_A ? 'A' : start === START_B ? 'B' : start === START_C ? 'C' : null;
	if (startSet === null) throw new Error(`does not begin with a start code (${start})`);

	const data = symbols.slice(1, -2);
	const check = symbols[symbols.length - 2];
	const sum = data.reduce((s, v, i) => s + (i + 1) * v, start);
	if (sum % 103 !== check) throw new Error(`check symbol ${check}, expected ${sum % 103}`);

	let set: 'A' | 'B' | 'C' = startSet;
	let text = '';
	for (const v of data) {
		if (set === 'C') {
			if (v < 100) text += String(v).padStart(2, '0');
			else if (v === 100) set = 'B';
			else if (v === 101) set = 'A';
			else throw new Error(`unsupported set C function ${v}`);
		} else if (v === 99) set = 'C';
		else if (set === 'B' && v === 100) throw new Error('FNC4 is not supported');
		else if (set === 'A' && v === 101) throw new Error('FNC4 is not supported');
		else if (v === 100) set = 'B';
		else if (v === 101) set = 'A';
		else if (v >= 96) throw new Error(`unsupported function symbol ${v}`);
		else if (set === 'B') text += String.fromCharCode(v + 32);
		else text += String.fromCharCode(v < 64 ? v + 32 : v - 64);
	}
	return { text, startSet, symbols };
}

/** What a scanner sees: the encoder's modules inside a quiet zone either side. */
function scanRow(text: string, quiet = CODE128_QUIET_ZONE_MODULES): string {
	return '0'.repeat(quiet) + code128BModules(text) + '0'.repeat(quiet);
}

function rowFromWidths(widths: string): string {
	return [...widths].map((w, i) => (i % 2 === 0 ? '1' : '0').repeat(Number(w))).join('');
}

function rowFromSymbols(symbols: number[]): string {
	return symbols.map((v) => ISO_15417_TABLE[v]).join('') + '11';
}

// --- The decoder itself, against published and hand-built codes -----------

test('decoder: reads the published PJJ123C example (Code 128 A, check 54)', () => {
	// en.wikipedia.org/wiki/Code_128 § Check digit calculation:
	// START A 103, P 48, J 42, J 42, 1 17, 2 18, 3 19, C 35 → Σ 878 → 878 mod 103 = 54.
	const row = '0'.repeat(10) + rowFromSymbols([103, 48, 42, 42, 17, 18, 19, 35, 54, 106]) + '0'.repeat(10);
	const decoded = decode(row);
	assert.equal(decoded.text, 'PJJ123C');
	assert.equal(decoded.startSet, 'A');
});

test('decoder: reads set C digit pairs, so it is not a set-B-only reader', () => {
	// START C 105, 12, 34 → 105 + 12 + 68 = 185 → 185 mod 103 = 82.
	const row = '0'.repeat(10) + rowFromSymbols([105, 12, 34, 82, 106]) + '0'.repeat(10);
	assert.equal(decode(row).text, '1234');
});

test('decoder: refuses what a scanner refuses', () => {
	const good = scanRow('A123456');
	assert.equal(decode(good).text, 'A123456');
	// One data module flipped.
	const at = 10 + 11 * 2 + 3;
	const flipped = good.slice(0, at) + (good[at] === '1' ? '0' : '1') + good.slice(at + 1);
	assert.throws(() => decode(flipped));
	// A valid symbol swapped for another: the check symbol no longer agrees.
	const swapped = '0'.repeat(10) + rowFromSymbols([104, 33, 18, 17, 19, 20, 21, 22, 63, 106]) + '0'.repeat(10);
	assert.throws(() => decode(swapped), /check symbol/);
	// Quiet zone one module short on either side.
	assert.throws(() => decode(good.slice(1)), /leading quiet zone/);
	assert.throws(() => decode(good.slice(0, -1)), /trailing quiet zone/);
	// The STOP pattern without its terminating bar.
	const noFinalBar = good.slice(0, good.length - 12) + '0'.repeat(12);
	assert.throws(() => decode(noFinalBar));
});

// --- The encoder, read back ------------------------------------------------

const REAL_SHAPED = [
	'A1', // shortest valid
	'A12', // even digit count — a set C encoder would pair these
	'A123', // odd digit count — a set C encoder needs a set switch
	'A12345',
	'A123456', // the common 6-digit shape
	'A4027501', // the common 7-digit shape
	'A9999999', // the largest 7-digit number
	'A100000',
	'A0', // the regex admits a lone zero and leading zeros, so they must scan too
	'A0001',
	'A123456789012', // the 12-digit maximum parkrun-import accepts
	'A999999999999',
];

test('encode → decode round-trips real-shaped athlete numbers', () => {
	for (const number of REAL_SHAPED) {
		assert.equal(decode(scanRow(number)).text, number, number);
	}
});

test('every check symbol value 0–102 round-trips', () => {
	// The data symbols of an athlete number are only `A` and the ten digits,
	// but the check symbol can be any of the 103 data values; walk numbers
	// until each has been the check at least once, so a wrong row anywhere in
	// the encoder's table reaches the decoder.
	const seen = new Set<number>();
	for (let n = 1; seen.size < 103 && n < 100_000; n++) {
		const number = `A${n}`;
		const decoded = decode(scanRow(number));
		assert.equal(decoded.text, number);
		seen.add(decoded.symbols[decoded.symbols.length - 2]);
	}
	assert.equal(seen.size, 103);
});

test('code set: always B, one symbol per character — never the shortest for long digit runs', () => {
	// The encoder deliberately never switches to set C (parkrun_barcode.ts
	// header): every scanner reads any set, and a fixed one-symbol-per-
	// character layout leaves no set-switching logic to get wrong. The cost is
	// width: A123456789012 is 16 symbols where `A`, CODE C and six digit pairs
	// would be 11. Pinned so a change to that choice is a deliberate one.
	for (const number of REAL_SHAPED) {
		const decoded = decode(scanRow(number));
		assert.equal(decoded.startSet, 'B', number);
		assert.equal(decoded.symbols.length, number.length + 3, number);
		assert.ok(!decoded.symbols.slice(1, -2).some((v) => v >= 96), `${number}: no set switch`);
	}
});

test('the drawn bars (what ParkrunBarcode.svelte renders) scan with their quiet zone', () => {
	// The component draws a white viewBox of modules + 2 × quiet zone and one
	// rect per bar at x = quiet zone + bar.start.
	for (const number of REAL_SHAPED) {
		const modules = code128BModules(number);
		const row = Array.from({ length: modules.length + 2 * CODE128_QUIET_ZONE_MODULES }, () => '0');
		for (const bar of barcodeBars(modules)) {
			for (let x = 0; x < bar.width; x++) row[CODE128_QUIET_ZONE_MODULES + bar.start + x] = '1';
		}
		assert.equal(decode(row.join('')).text, number, number);
	}
});

// --- Hand-computed references, independent of both encoders ---------------
//
// A1:  START B 104 + 1×A(33) + 2×'1'(17)              = 171 → 171 mod 103 = 68
// A12: START B 104 + 1×33 + 2×17 + 3×'2'(18)          = 225 → 225 mod 103 = 19
// A0:  START B 104 + 1×33 + 2×'0'(16)                 = 169 → 169 mod 103 = 66
// A123456: 104 + 33 + 2×17 + 3×18 + 4×19 + 5×20 + 6×21 + 7×22 = 681 → 681 mod 103 = 63
// Widths per value are read off ISO/IEC 15417 Table 1: START B 104 = 211214,
// A 33 = 111323, '0' 16 = 123122, '1' 17 = 123221, '2' 18 = 223211,
// 19 = 221132, 66 = 121421, 68 = 141221, STOP = 2331112.

test('hand-computed vectors from the Code 128 table', () => {
	const hand: Array<[string, number[], string]> = [
		['A1', [104, 33, 17, 68, 106], '211214' + '111323' + '123221' + '141221' + '2331112'],
		['A12', [104, 33, 17, 18, 19, 106], '211214' + '111323' + '123221' + '223211' + '221132' + '2331112'],
		['A0', [104, 33, 16, 66, 106], '211214' + '111323' + '123122' + '121421' + '2331112'],
	];
	for (const [number, symbols, widths] of hand) {
		assert.deepEqual(code128BSymbols(number), symbols, number);
		assert.equal(code128BModules(number), rowFromWidths(widths), number);
	}
	assert.equal(code128BSymbols('A123456').at(-2), 63);
});

// --- The shared golden vectors ---------------------------------------------

interface Vectors {
	quiet_zone_modules: number;
	cases: Array<{ input: string; symbols: number[]; widths: string; modules: number }>;
}

const VECTORS: Vectors = JSON.parse(
	readFileSync(
		join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..', '..', 'fixtures', 'parkrun_barcode_vectors.json'),
		'utf8',
	),
);

test('shared vectors: the encoder matches every committed width sequence', () => {
	assert.equal(VECTORS.quiet_zone_modules, CODE128_QUIET_ZONE_MODULES);
	assert.ok(VECTORS.cases.length >= 10);
	for (const c of VECTORS.cases) {
		assert.deepEqual(code128BSymbols(c.input), c.symbols, c.input);
		assert.equal(code128BModules(c.input), rowFromWidths(c.widths), c.input);
		assert.equal(code128BModules(c.input).length, c.modules, c.input);
	}
});

test('shared vectors: every committed width sequence decodes to its input', () => {
	const q = '0'.repeat(VECTORS.quiet_zone_modules);
	for (const c of VECTORS.cases) {
		assert.equal(decode(q + rowFromWidths(c.widths) + q).text, c.input, c.input);
	}
});
