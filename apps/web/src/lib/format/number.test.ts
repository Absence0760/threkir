import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatDecimal, formatInteger, formatSignedInteger } from './number';

// de uses "." for grouping + "," for decimal; en/ja use "," + ".". fr uses a
// narrow no-break space for grouping (ICU-version-sensitive), so fr is
// asserted on the decimal separator only, not the group separator.

test('formatDecimal: fixed fraction digits per locale', () => {
	assert.equal(formatDecimal(5.21, 2, 'en'), '5.21');
	assert.equal(formatDecimal(5.21, 2, 'de'), '5,21');
	assert.equal(formatDecimal(5.21, 2, 'ja'), '5.21');
	assert.equal(formatDecimal(5.21, 2, 'pt-BR'), '5,21');
	assert.equal(formatDecimal(5.21, 2, 'pt-PT'), '5,21');
	// Pads to the requested width like toFixed did.
	assert.equal(formatDecimal(5, 2, 'en'), '5.00');
	assert.equal(formatDecimal(6.5, 2, 'de'), '6,50');
	assert.equal(formatDecimal(8.123, 1, 'en'), '8.1');
});

test('formatDecimal: comma-decimal locales use a comma', () => {
	for (const loc of ['de', 'fr', 'es', 'pt-BR', 'pt-PT']) {
		assert.match(formatDecimal(5.21, 2, loc), /^5,21$/, loc);
	}
});

test('formatDecimal: grouping + decimal together', () => {
	assert.equal(formatDecimal(1234.5, 1, 'en'), '1,234.5');
	assert.equal(formatDecimal(1234.5, 1, 'de'), '1.234,5');
});

test('formatInteger: groups thousands per locale', () => {
	assert.equal(formatInteger(1234, 'en'), '1,234');
	assert.equal(formatInteger(1234, 'de'), '1.234');
	assert.equal(formatInteger(1234, 'ja'), '1,234');
	// Sub-thousand values are ungrouped everywhere.
	assert.equal(formatInteger(842, 'en'), '842');
	assert.equal(formatInteger(842, 'de'), '842');
});

test('default (undefined) locale returns a string without throwing', () => {
	assert.equal(typeof formatDecimal(5.21, 2), 'string');
	assert.equal(typeof formatInteger(1234), 'string');
});

test('repeated calls are stable (memoised formatter)', () => {
	assert.equal(formatDecimal(5.21, 2, 'de'), formatDecimal(5.21, 2, 'de'));
	assert.equal(formatInteger(1234, 'en'), formatInteger(1234, 'en'));
});

test('degenerate input never reaches the label as NaN, ∞ or a signed zero', () => {
	// A training-stress balance of -0.04 rendered "-0.0"; a 0 m distance
	// divided to NaN rendered "NaN km". Same table as `formatFixed degenerate
	// input` in number_format_test.dart.
	const cases: Array<[number, number, string]> = [
		[Number.NaN, 1, '—'],
		[Number.POSITIVE_INFINITY, 1, '—'],
		[Number.NEGATIVE_INFINITY, 1, '—'],
		[-0, 1, '0.0'],
		[-0.04, 1, '0.0'],
		[-0.05, 1, '-0.1'],
		[-0.3, 1, '-0.3'],
		[-0.004, 2, '0.00'],
		[-0.3, 0, '0'],
		[-0.5, 0, '-1'],
	];
	for (const [value, digits, expected] of cases) {
		assert.equal(formatDecimal(value, digits, 'en'), expected, `formatDecimal(${value}, ${digits})`);
	}
	assert.equal(formatDecimal(-0.04, 1, 'de'), '0,0');
	assert.equal(formatInteger(-0.3, 'en'), '0');
	assert.equal(formatInteger(Number.NaN, 'en'), '—');
});

test('formatSignedInteger: a sign either side of zero, never "-0" or "+0"', () => {
	const cases: Array<[number, string]> = [
		[12.4, '+12'],
		[0.3, '0'],
		[0, '0'],
		[-0, '0'],
		[-0.3, '0'],
		[-0.5, '0'],
		[-0.6, '-1'],
		[-12.4, '-12'],
		[Number.NaN, '—'],
		[Number.NEGATIVE_INFINITY, '—'],
	];
	for (const [value, expected] of cases) {
		assert.equal(formatSignedInteger(value, 'en'), expected, `formatSignedInteger(${value})`);
	}
});
