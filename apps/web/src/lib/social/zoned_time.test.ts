import { test } from 'node:test';
import assert from 'node:assert/strict';
import { instantForWallClock, isKnownTimeZone, wallClockIn, zoneOffsetMs } from './zoned_time';

const H = 3_600_000;

test('wallClockIn reads the instant on the zone clock, weekday included', () => {
	// 01:30Z on Thursday is 21:30 on Wednesday in New York (EDT).
	assert.deepEqual(wallClockIn(Date.parse('2026-10-22T01:30:00Z'), 'America/New_York'), {
		year: 2026,
		month: 10,
		day: 21,
		hour: 21,
		minute: 30,
		second: 0,
		weekday: 3
	});
	assert.equal(wallClockIn(Date.parse('2026-10-20T23:30:00Z'), 'Asia/Kolkata').weekday, 3);
});

test('wallClockIn reports midnight as hour 0, never 24', () => {
	assert.equal(wallClockIn(Date.parse('2026-10-22T04:00:00Z'), 'America/New_York').hour, 0);
});

test('zoneOffsetMs follows the zone across DST, to the half hour', () => {
	assert.equal(zoneOffsetMs(Date.parse('2026-10-22T01:30:00Z'), 'America/New_York'), -4 * H);
	assert.equal(zoneOffsetMs(Date.parse('2026-11-05T02:30:00Z'), 'America/New_York'), -5 * H);
	assert.equal(zoneOffsetMs(Date.parse('2026-06-01T00:00:00Z'), 'Australia/Lord_Howe'), 10.5 * H);
	assert.equal(zoneOffsetMs(Date.parse('2026-06-01T00:00:00.789Z'), 'UTC'), 0);
});

test('instantForWallClock resolves an ordinary reading to its one instant', () => {
	const t = instantForWallClock(
		{ year: 2026, month: 11, day: 4, hour: 21, minute: 30, second: 0 },
		'America/New_York'
	);
	assert.equal(t.toISOString(), '2026-11-05T02:30:00.000Z');
});

test('instantForWallClock moves a spring-forward gap reading forward', () => {
	// 02:30 does not exist on 14 Mar 2027 in New York; RFC 5545 §3.3.5 takes
	// the pre-gap offset, which lands on 03:30 EDT.
	const t = instantForWallClock(
		{ year: 2027, month: 3, day: 14, hour: 2, minute: 30, second: 0 },
		'America/New_York'
	);
	assert.equal(t.toISOString(), '2027-03-14T07:30:00.000Z');
	assert.equal(wallClockIn(t, 'America/New_York').hour, 3);
});

test('instantForWallClock takes the earlier instant of a fall-back reading', () => {
	const t = instantForWallClock(
		{ year: 2026, month: 11, day: 1, hour: 1, minute: 30, second: 0 },
		'America/New_York'
	);
	assert.equal(t.toISOString(), '2026-11-01T05:30:00.000Z');
});

test('instantForWallClock handles the southern hemisphere and a 30-minute shift', () => {
	assert.equal(
		instantForWallClock({ year: 2026, month: 4, day: 8, hour: 6, minute: 0, second: 0 }, 'Pacific/Auckland').toISOString(),
		'2026-04-07T18:00:00.000Z'
	);
	// Lord Howe springs forward 02:00 -> 02:30 on 4 Oct 2026.
	assert.equal(
		instantForWallClock({ year: 2026, month: 10, day: 4, hour: 2, minute: 15, second: 0 }, 'Australia/Lord_Howe').toISOString(),
		'2026-10-03T15:45:00.000Z'
	);
});

test('isKnownTimeZone accepts IANA names and refuses anything else', () => {
	assert.equal(isKnownTimeZone('Europe/Berlin'), true);
	assert.equal(isKnownTimeZone('UTC'), true);
	assert.equal(isKnownTimeZone('Mars/Olympus'), false);
	assert.equal(isKnownTimeZone(''), false);
	assert.equal(isKnownTimeZone(null), false);
});
