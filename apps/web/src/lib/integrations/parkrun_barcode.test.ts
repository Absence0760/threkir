import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	CODE128_PATTERNS,
	CODE128_STOP,
	barcodeBars,
	code128BModules,
	code128BSymbols,
	normalizeParkrunAthleteNumber,
} from './parkrun_barcode';

// Reference module strings built from JsBarcode's CODE128 `BARS` table, an
// encoder independent of the width table under test.
const REF_A123456 =
	'1101001000010100011000100111001101100111001011001011100110010011101101110010011001110100101001100001100011101011';
const REF_A4027501 =
	'110100100001010001100011001001110100111011001100111001011101101110110111001001001110110010011100110100101100001100011101011';
const REF_A1 = '110100100001010001100010011100110100001001101100011101011';

test('athlete number: canonical numbers pass unchanged', () => {
	assert.equal(normalizeParkrunAthleteNumber('A123456'), 'A123456');
	assert.equal(normalizeParkrunAthleteNumber('A1'), 'A1');
	assert.equal(normalizeParkrunAthleteNumber('A123456789012'), 'A123456789012');
});

test('athlete number: whitespace and a lowercase a are forgiven', () => {
	assert.equal(normalizeParkrunAthleteNumber('  a123456 '), 'A123456');
	assert.equal(normalizeParkrunAthleteNumber('A 123 456'), 'A123456');
});

test('athlete number: anything else is refused', () => {
	assert.equal(normalizeParkrunAthleteNumber(null), null);
	assert.equal(normalizeParkrunAthleteNumber(undefined), null);
	assert.equal(normalizeParkrunAthleteNumber(''), null);
	assert.equal(normalizeParkrunAthleteNumber('   '), null);
	assert.equal(normalizeParkrunAthleteNumber('123456'), null);
	assert.equal(normalizeParkrunAthleteNumber('A'), null);
	assert.equal(normalizeParkrunAthleteNumber('B123456'), null);
	assert.equal(normalizeParkrunAthleteNumber('A12345a'), null);
	assert.equal(normalizeParkrunAthleteNumber('A1234567890123'), null);
	assert.equal(normalizeParkrunAthleteNumber('A١٢٣'), null);
});

test('pattern table: 107 symbols, 11 modules each, STOP 13', () => {
	assert.equal(CODE128_PATTERNS.length, 107);
	CODE128_PATTERNS.forEach((p, i) => {
		const sum = [...p].reduce((s, d) => s + Number(d), 0);
		assert.equal(sum, i === CODE128_STOP ? 13 : 11, `symbol ${i}`);
		assert.equal(p.length, i === CODE128_STOP ? 7 : 6, `symbol ${i}`);
	});
	assert.equal(new Set(CODE128_PATTERNS).size, 107);
});

test('symbols: START B, set-B values, mod-103 check, STOP', () => {
	assert.deepEqual(code128BSymbols('A123456'), [104, 33, 17, 18, 19, 20, 21, 22, 63, 106]);
	assert.deepEqual(code128BSymbols('A1'), [104, 33, 17, 68, 106]);
});

test('symbols: refuses empty and non-printable input', () => {
	assert.throws(() => code128BSymbols(''), RangeError);
	assert.throws(() => code128BSymbols('A\n1'), RangeError);
	assert.throws(() => code128BSymbols('Aé'), RangeError);
});

test('modules match the reference encodings', () => {
	assert.equal(code128BModules('A123456'), REF_A123456);
	assert.equal(code128BModules('A4027501'), REF_A4027501);
	assert.equal(code128BModules('A1'), REF_A1);
});

test('modules: 11 per symbol plus 13 for STOP, bar at both ends', () => {
	const modules = code128BModules('A123456');
	assert.equal(modules.length, 11 * 9 + 13);
	assert.equal(modules[0], '1');
	assert.equal(modules[modules.length - 1], '1');
});

test('bars: one run per contiguous bar', () => {
	assert.deepEqual(barcodeBars('0110100111'), [
		{ start: 1, width: 2 },
		{ start: 4, width: 1 },
		{ start: 7, width: 3 },
	]);
	assert.deepEqual(barcodeBars(''), []);
	const bars = barcodeBars(REF_A1);
	assert.equal(bars.reduce((s, b) => s + b.width, 0), [...REF_A1].filter((c) => c === '1').length);
});
