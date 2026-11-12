import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseStravaCsvDateToIso } from './strava-zip-date';

test('parses the documented no-zone format as UTC, not viewer-local', () => {
	// "Apr 15, 2026, 1:00:00 PM" is UTC per Strava's docs but carries no zone
	// designator. The instant must be 13:00:00Z regardless of the importer's
	// local timezone.
	assert.equal(parseStravaCsvDateToIso('Apr 15, 2026, 1:00:00 PM'), '2026-04-15T13:00:00.000Z');
});

test('a midnight no-zone run stays on the same UTC calendar day', () => {
	// The regression: a local-zone parse would roll this to the previous or
	// next day for viewers behind/ahead of UTC.
	assert.equal(parseStravaCsvDateToIso('Apr 15, 2026, 12:00:00 AM'), '2026-04-15T00:00:00.000Z');
});

test('12 PM noon stays at hour 12 UTC', () => {
	assert.equal(parseStravaCsvDateToIso('Apr 15, 2026, 12:00:00 PM'), '2026-04-15T12:00:00.000Z');
});

test('24-hour no-zone input is treated as UTC', () => {
	assert.equal(parseStravaCsvDateToIso('Apr 15, 2026, 19:45:30'), '2026-04-15T19:45:30.000Z');
});

test('long month name resolves via first-3-char slice', () => {
	assert.equal(parseStravaCsvDateToIso('April 9, 2026, 7:30:00 AM'), '2026-04-09T07:30:00.000Z');
});

test('month name is case-insensitive', () => {
	assert.equal(
		parseStravaCsvDateToIso('apr 9, 2026, 7:30:00 am'),
		parseStravaCsvDateToIso('APR 9, 2026, 7:30:00 AM'),
	);
});

test('an already-zoned ISO value is left untouched (not re-shifted)', () => {
	// Defers to the native parser, which honours the embedded offset.
	assert.equal(parseStravaCsvDateToIso('2026-04-09T07:30:00Z'), '2026-04-09T07:30:00.000Z');
	assert.equal(parseStravaCsvDateToIso('2026-04-09T07:30:00+02:00'), '2026-04-09T05:30:00.000Z');
});

test('returns null for empty / unparseable input', () => {
	assert.equal(parseStravaCsvDateToIso(''), null);
	assert.equal(parseStravaCsvDateToIso(null), null);
	assert.equal(parseStravaCsvDateToIso(undefined), null);
	assert.equal(parseStravaCsvDateToIso('not a date'), null);
});

test('returns null when the month name is unknown', () => {
	assert.equal(parseStravaCsvDateToIso('Xyz 1, 2026, 1:00:00 AM'), null);
});

/// Run `fn` with the process in a zone far from UTC, so a parse that reads a
/// zone-less value as local time shows up as an hours-wrong instant.
function inZone<T>(tz: string, fn: () => T): T {
	const prev = process.env.TZ;
	process.env.TZ = tz;
	try {
		return fn();
	} finally {
		if (prev === undefined) delete process.env.TZ;
		else process.env.TZ = prev;
	}
}

test('a zone-less ISO datetime is read as UTC in every importer zone', () => {
	for (const tz of ['America/Los_Angeles', 'Asia/Tokyo', 'UTC']) {
		inZone(tz, () => {
			assert.equal(parseStravaCsvDateToIso('2026-04-15T13:00:00'), '2026-04-15T13:00:00.000Z', tz);
			assert.equal(parseStravaCsvDateToIso('2026-04-15 13:00:00'), '2026-04-15T13:00:00.000Z', tz);
			assert.equal(parseStravaCsvDateToIso('2026-04-15T00:30'), '2026-04-15T00:30:00.000Z', tz);
		});
	}
});

test('a day-first export cell is read as UTC, not the importer zone', () => {
	inZone('America/New_York', () => {
		assert.equal(parseStravaCsvDateToIso('15 Apr 2026, 13:00:00'), '2026-04-15T13:00:00.000Z');
		assert.equal(parseStravaCsvDateToIso('5 April 2026, 1:00:00 AM'), '2026-04-05T01:00:00.000Z');
	});
});

test('a zone-less shape it does not recognise is null, never a local-zone guess', () => {
	// The native parser reads these in the importer's zone. A null is
	// reported as a failed row; a shifted instant is silently wrong forever.
	inZone('Asia/Tokyo', () => {
		assert.equal(parseStravaCsvDateToIso('04/15/2026 13:00:00'), null);
		assert.equal(parseStravaCsvDateToIso('Apr 15, 2026'), null);
	});
});

test('a value that carries its own zone still defers to that zone', () => {
	inZone('Asia/Tokyo', () => {
		assert.equal(parseStravaCsvDateToIso('2026-04-15T13:00:00-0700'), '2026-04-15T20:00:00.000Z');
		assert.equal(parseStravaCsvDateToIso('Wed, 15 Apr 2026 13:00:00 GMT'), '2026-04-15T13:00:00.000Z');
		assert.equal(parseStravaCsvDateToIso('2026-04-15'), '2026-04-15T00:00:00.000Z', 'date-only ISO is UTC');
	});
});

test('an impossible calendar date is null rather than rolled into the next month', () => {
	// Date.UTC silently rolls Feb 30 to Mar 2 and Apr 31 to May 1, which
	// would file the run on a day it did not happen.
	assert.equal(parseStravaCsvDateToIso('Feb 30, 2026, 1:00:00 PM'), null);
	assert.equal(parseStravaCsvDateToIso('Apr 31, 2026, 1:00:00 PM'), null);
	assert.equal(parseStravaCsvDateToIso('Feb 29, 2025, 1:00:00 PM'), null);
	assert.equal(parseStravaCsvDateToIso('Feb 29, 2024, 1:00:00 PM'), '2024-02-29T13:00:00.000Z');
	assert.equal(parseStravaCsvDateToIso('2026-02-30T10:00:00'), null);
});

test('an out-of-range clock is null rather than rolled into the next day', () => {
	assert.equal(parseStravaCsvDateToIso('Apr 15, 2026, 24:00:00'), null);
	assert.equal(parseStravaCsvDateToIso('Apr 15, 2026, 23:60:00'), null);
	assert.equal(parseStravaCsvDateToIso('Apr 15, 2026, 23:59:60'), null);
	assert.equal(parseStravaCsvDateToIso('Apr 15, 2026, 23:59:59'), '2026-04-15T23:59:59.000Z');
	assert.equal(parseStravaCsvDateToIso('Apr 0, 2026, 1:00:00 PM'), null);
});
