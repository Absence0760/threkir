import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { HOME_REDESIGN_DATE, formatPct, formatWeekStart, isCurrentWeek, weekContains } from './home_metrics.ts';

test('the redesign day falls in the ISO week that starts Monday 2 November 2026', () => {
	assert.equal(weekContains('2026-11-02', HOME_REDESIGN_DATE), true);
	assert.equal(weekContains('2026-11-09', HOME_REDESIGN_DATE), false);
	assert.equal(weekContains('2026-10-26', HOME_REDESIGN_DATE), false);
});

test('a week holds its Monday and its Sunday, not the next Monday', () => {
	assert.equal(weekContains('2026-11-09', '2026-11-09'), true);
	assert.equal(weekContains('2026-11-09', '2026-11-15'), true);
	assert.equal(weekContains('2026-11-09', '2026-11-16'), false);
	assert.equal(weekContains('not-a-date', '2026-11-09'), false);
});

test('the current week is read in UTC', () => {
	// 23:30 on Sunday 15 November in UTC-5 is Monday 16 November in UTC.
	const now = new Date('2026-11-15T23:30:00-05:00');
	assert.equal(isCurrentWeek('2026-11-16', now), true);
	assert.equal(isCurrentWeek('2026-11-09', now), false);
});

test('a week start formats as a UTC date in the reader locale', () => {
	assert.equal(formatWeekStart('2026-11-02', 'en'), 'Nov 2, 2026');
	assert.equal(formatWeekStart('garbage', 'en'), 'garbage');
});

test('a percentage keeps one decimal, and a null stays null', () => {
	assert.equal(formatPct(33.3, 'en'), '33.3%');
	assert.equal(formatPct(40, 'en'), '40.0%');
	assert.equal(formatPct(null, 'en'), null);
});
