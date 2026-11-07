import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	HOURS_MAX_DIGITS,
	MAX_RUN_DURATION_S,
	MINUTES_SECONDS_MAX_DIGITS,
	SLOW_PACE_CONFIRM_S_PER_KM,
	isImplausiblySlow,
	isPlausibleRunDuration,
	validateManualDuration,
} from './run_duration';

test('the bound is ten days and the hours box is wide enough to type it', () => {
	assert.equal(MAX_RUN_DURATION_S, 10 * 24 * 3600);
	assert.equal(String(MAX_RUN_DURATION_S / 3600).length, HOURS_MAX_DIGITS);
	assert.equal(String(59).length, MINUTES_SECONDS_MAX_DIGITS);
	assert.equal(SLOW_PACE_CONFIRM_S_PER_KM, 3600);
});

test('a typed duration sums its three boxes', () => {
	assert.deepEqual(validateManualDuration('0', '21', '34'), { ok: true, seconds: 1294 });
	assert.deepEqual(validateManualDuration('', '21', ''), { ok: true, seconds: 1260 });
	assert.deepEqual(validateManualDuration(' 1 ', '', ''), { ok: true, seconds: 3600 });
});

test('the issue #1300 run — 12333 in the hours box — is refused', () => {
	assert.deepEqual(validateManualDuration('12333', '21', '34'), { ok: false, error: 'tooLong' });
});

test('the bound itself is allowed and one second past it is not', () => {
	assert.deepEqual(validateManualDuration('240', '0', '0'), { ok: true, seconds: 864_000 });
	assert.deepEqual(validateManualDuration('240', '0', '1'), { ok: false, error: 'tooLong' });
	assert.deepEqual(validateManualDuration('112', '0', '0'), { ok: true, seconds: 403_200 });
});

test('minutes and seconds are clock fields', () => {
	assert.deepEqual(validateManualDuration('0', '60', '0'), { ok: false, error: 'minutesOutOfRange' });
	assert.deepEqual(validateManualDuration('0', '0', '60'), { ok: false, error: 'secondsOutOfRange' });
	assert.deepEqual(validateManualDuration('0', '59', '59'), { ok: true, seconds: 3599 });
});

test('an empty or all-zero duration is refused', () => {
	assert.deepEqual(validateManualDuration('', '', ''), { ok: false, error: 'zero' });
	assert.deepEqual(validateManualDuration('0', '00', '0'), { ok: false, error: 'zero' });
});

test('anything but digits is invalid, never reinterpreted', () => {
	assert.deepEqual(validateManualDuration('1.5', '', ''), { ok: false, error: 'invalid' });
	assert.deepEqual(validateManualDuration('-1', '', ''), { ok: false, error: 'invalid' });
	assert.deepEqual(validateManualDuration('', '3e1', ''), { ok: false, error: 'invalid' });
});

test('a box too long for any integer type is out of range, not a crash', () => {
	const huge = '99999999999999999999';
	assert.deepEqual(validateManualDuration(huge, '', ''), { ok: false, error: 'tooLong' });
	assert.deepEqual(validateManualDuration('', huge, ''), { ok: false, error: 'minutesOutOfRange' });
	assert.deepEqual(validateManualDuration('0000000000001', '', ''), { ok: true, seconds: 3600 });
});

test('isPlausibleRunDuration is the inclusive 0..bound range', () => {
	assert.equal(isPlausibleRunDuration(0), true);
	assert.equal(isPlausibleRunDuration(864_000), true);
	assert.equal(isPlausibleRunDuration(864_001), false);
	assert.equal(isPlausibleRunDuration(44_400_094), false);
	assert.equal(isPlausibleRunDuration(-1), false);
	assert.equal(isPlausibleRunDuration(Number.NaN), false);
});

test('isImplausiblySlow flags the typo, not a real slow effort', () => {
	assert.equal(isImplausiblySlow(1294, 2000), false);
	assert.equal(isImplausiblySlow(44_400_094, 2000), true);
	assert.equal(isImplausiblySlow(403_200, 386_243), false);
	assert.equal(isImplausiblySlow(3600, 1000), false);
	assert.equal(isImplausiblySlow(3601, 1000), true);
});

test('isImplausiblySlow has no pace to judge without a distance or a duration', () => {
	assert.equal(isImplausiblySlow(3600, 0), false);
	assert.equal(isImplausiblySlow(0, 1000), false);
});
