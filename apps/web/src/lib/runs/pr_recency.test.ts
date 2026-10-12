import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { relativeAge } from './pr_recency';

const NOW = Date.parse('2026-05-01T12:00:00Z');

test('relativeAge — today / yesterday / days', () => {
	const noon = new Date(2026, 4, 1, 12, 0).getTime();
	assert.equal(relativeAge(local(2026, 5, 1, 8), noon), 'today');
	assert.equal(relativeAge(local(2026, 4, 30, 8), noon), 'yesterday');
	assert.equal(relativeAge(local(2026, 4, 28, 8), noon), '3 days ago');
});

test('relativeAge — weeks / months / years', () => {
	assert.equal(relativeAge('2026-04-20T12:00:00Z', NOW), 'a week ago');
	assert.equal(relativeAge('2026-04-01T12:00:00Z', NOW), '4 weeks ago');
	assert.equal(relativeAge('2026-02-20T12:00:00Z', NOW), '2 months ago');
	assert.equal(relativeAge('2024-04-15T12:00:00Z', NOW), '2 years ago');
	assert.equal(relativeAge('2025-04-15T12:00:00Z', NOW), 'a year ago');
});

test('relativeAge — invalid date yields empty string', () => {
	assert.equal(relativeAge('not-a-date', NOW), '');
});

// Calendar words count calendar days. Built from local wall-clock dates so the
// expectation holds in any zone the suite runs in.
const local = (y: number, mo: number, d: number, h: number, mi = 0) =>
	new Date(y, mo - 1, d, h, mi).toISOString();

test('relativeAge — last evening read this morning is yesterday, not today', () => {
	const now = new Date(2026, 4, 1, 8, 0).getTime();
	assert.equal(relativeAge(local(2026, 4, 30, 19), now), 'yesterday');
	assert.equal(relativeAge(local(2026, 4, 30, 23, 59), new Date(2026, 4, 1, 0, 1).getTime()), 'yesterday');
	assert.equal(relativeAge(local(2026, 5, 1, 0, 1), now), 'today');
});

test('relativeAge — whole calendar days across a month end and a DST change', () => {
	// 29 Mar 2026 is the EU spring-forward and 8 Mar the US one; either way the
	// local date difference is what counts.
	assert.equal(relativeAge(local(2026, 3, 27, 22), new Date(2026, 2, 30, 6, 0).getTime()), '3 days ago');
	assert.equal(relativeAge(local(2026, 3, 6, 23), new Date(2026, 2, 9, 1, 0).getTime()), '3 days ago');
	assert.equal(relativeAge(local(2026, 1, 31, 23), new Date(2026, 1, 1, 0, 30).getTime()), 'yesterday');
});

test('relativeAge — a date later than now (clock skew) reads as today', () => {
	const now = new Date(2026, 4, 1, 8, 0).getTime();
	assert.equal(relativeAge(local(2026, 5, 1, 9), now), 'today');
	assert.equal(relativeAge(local(2026, 5, 3, 9), now), 'today');
});
