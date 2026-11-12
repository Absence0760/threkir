import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	MAX_AGE_YEARS,
	birthYearOptions,
	composeIsoDate,
	datePartOrder,
	daysInMonth,
	isFuture,
	isPartial,
	splitIsoDate,
} from './birth_date';

test('daysInMonth: month lengths, leap years, and a 29th February before the year is picked', () => {
	assert.equal(daysInMonth(2001, 1), 31);
	assert.equal(daysInMonth(2001, 4), 30);
	assert.equal(daysInMonth(2001, 2), 28);
	assert.equal(daysInMonth(2000, 2), 29);
	assert.equal(daysInMonth(1900, 2), 28);
	assert.equal(daysInMonth(null, 2), 29);
	assert.equal(daysInMonth(null, 12), 31);
});

test('splitIsoDate / composeIsoDate round-trip a stored date', () => {
	assert.deepEqual(splitIsoDate('2001-12-09'), { year: 2001, month: 12, day: 9 });
	assert.equal(composeIsoDate({ year: 2001, month: 12, day: 9 }), '2001-12-09');
	assert.equal(composeIsoDate(splitIsoDate('1978-04-09')), '1978-04-09');
});

test('splitIsoDate: empty, malformed and impossible dates read as no date', () => {
	const none = { year: null, month: null, day: null };
	assert.deepEqual(splitIsoDate(''), none);
	assert.deepEqual(splitIsoDate(null), none);
	assert.deepEqual(splitIsoDate('2001-13-01'), none);
	assert.deepEqual(splitIsoDate('2001-02-29'), none);
	assert.deepEqual(splitIsoDate('2001-12-09T00:00:00Z'), none);
});

test('composeIsoDate: null until every part is picked, and for a day the month lacks', () => {
	assert.equal(composeIsoDate({ year: 2001, month: 12, day: null }), null);
	assert.equal(composeIsoDate({ year: null, month: 2, day: 29 }), null);
	assert.equal(composeIsoDate({ year: 2001, month: 2, day: 29 }), null);
	assert.equal(composeIsoDate({ year: 2004, month: 2, day: 29 }), '2004-02-29');
	assert.equal(composeIsoDate({ year: 2001, month: 4, day: 31 }), null);
});

test('isPartial: only a mix of picked and unpicked parts', () => {
	assert.equal(isPartial({ year: null, month: null, day: null }), false);
	assert.equal(isPartial({ year: 2001, month: 12, day: 9 }), false);
	assert.equal(isPartial({ year: 2001, month: null, day: null }), true);
	assert.equal(isPartial({ year: null, month: 3, day: 4 }), true);
});

test('birthYearOptions: newest first, this year back MAX_AGE_YEARS', () => {
	const years = birthYearOptions(new Date(2026, 9, 18));
	assert.equal(years[0], 2026);
	assert.equal(years.at(-1), 2026 - MAX_AGE_YEARS);
	assert.equal(years.length, MAX_AGE_YEARS + 1);
});

test('isFuture: compares against the local calendar day', () => {
	const today = new Date(2026, 9, 18, 23, 30);
	assert.equal(isFuture({ year: 2026, month: 10, day: 18 }, today), false);
	assert.equal(isFuture({ year: 2026, month: 10, day: 19 }, today), true);
	assert.equal(isFuture({ year: 2026, month: 11, day: null }, today), false);
});

test('datePartOrder: the locale\'s own written order', () => {
	assert.deepEqual(datePartOrder('en-US'), ['month', 'day', 'year']);
	assert.deepEqual(datePartOrder('en-GB'), ['day', 'month', 'year']);
	assert.deepEqual(datePartOrder('de'), ['day', 'month', 'year']);
	assert.deepEqual(datePartOrder('ja'), ['year', 'month', 'day']);
	assert.deepEqual(datePartOrder('pt-BR'), ['day', 'month', 'year']);
});
