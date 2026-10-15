import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { DEGENERATE_NUMBER, degenerateStrings } from './degenerate-text.ts';

const HERE = dirname(fileURLToPath(import.meta.url));
const MOBILE_SWEEP = join(
	HERE,
	'..',
	'..',
	'..',
	'mobile_android',
	'test',
	'rendered_text_sweep.dart'
);

test('NaN, infinities and negative zeros are degenerate', () => {
	for (const s of [
		'NaN',
		'Pace NaN:NaN /km',
		'Infinity:NaN',
		'∞ km',
		'-0',
		'-0 km',
		'TSB -0',
		'-0.0',
		'-0.00 km',
		'-0,0',
		'-0:00',
		'−0',
		'(-0)'
	]) {
		assert.ok(DEGENERATE_NUMBER.test(s), `${JSON.stringify(s)} should be degenerate`);
	}
});

test('dates, zones, real negatives and ordinary zeros are not', () => {
	for (const s of [
		'0',
		'0 km',
		'0:00',
		'-1',
		'-0.05',
		'-0:30 /km',
		'2026-04-05',
		'UTC-0',
		'run-0',
		'10-0 win',
		'Nancy',
		'Infinityish',
		'--:--',
		'—'
	]) {
		assert.ok(!DEGENERATE_NUMBER.test(s), `${JSON.stringify(s)} should not be degenerate`);
	}
});

test('degenerateStrings names only the offenders', () => {
	assert.deepEqual(degenerateStrings(['5:00 /km', 'NaN:NaN', '2026-10-15', '-0 kg']), [
		'NaN:NaN',
		'-0 kg'
	]);
	assert.deepEqual(degenerateStrings([]), []);
});

test('the pattern is the mobile sweep pattern', () => {
	const dart = readFileSync(MOBILE_SWEEP, 'utf8');
	const match = /final degenerateNumber = RegExp\(\s*r'([^']+)'/.exec(dart);
	assert.ok(match, 'rendered_text_sweep.dart no longer declares degenerateNumber as a raw string');
	assert.equal(DEGENERATE_NUMBER.source, match[1]);
	assert.ok(DEGENERATE_NUMBER.unicode, 'the Dart pattern is unicode: true; this one must be /u');
});
