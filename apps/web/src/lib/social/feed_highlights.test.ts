import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	groupHighlights,
	highlightsShowFor,
	interleaveHighlights,
	needsMoreHighlights,
	type HighlightAward,
} from './feed_highlights';

const utcDay = (iso: string) => iso.slice(0, 10);

function award(id: string, authorId: string, earnedAt: string): HighlightAward {
	return { authorId, badge: { id, earned_at: earnedAt } };
}

interface Entry {
	id: string;
	started_at: string;
}
const at = (e: Entry) => e.started_at;
function entry(id: string, startedAt: string): Entry {
	return { id, started_at: startedAt };
}

test('groupHighlights: no awards, no highlights', () => {
	assert.deepEqual(groupHighlights([], utcDay), []);
});

test('groupHighlights: one award is a highlight of one', () => {
	const g = groupHighlights([award('b1', 'u1', '2026-06-10T08:00:00Z')], utcDay);
	assert.equal(g.length, 1);
	assert.equal(g[0].key, 'u1|2026-06-10');
	assert.equal(g[0].awards.length, 1);
	assert.equal(g[0].at, '2026-06-10T08:00:00Z');
});

test('groupHighlights: one person, one day, several awards collapse, newest first', () => {
	const g = groupHighlights(
		[
			award('b1', 'u1', '2026-06-10T08:00:00Z'),
			award('b2', 'u1', '2026-06-10T19:00:00Z'),
			award('b3', 'u1', '2026-06-10T12:00:00Z'),
		],
		utcDay
	);
	assert.equal(g.length, 1);
	assert.deepEqual(
		g[0].awards.map((a) => a.badge.id),
		['b2', 'b3', 'b1']
	);
	assert.equal(g[0].at, '2026-06-10T19:00:00Z');
});

test('groupHighlights: the same person on two days stays two rows', () => {
	const g = groupHighlights(
		[award('b1', 'u1', '2026-06-10T08:00:00Z'), award('b2', 'u1', '2026-06-11T08:00:00Z')],
		utcDay
	);
	assert.deepEqual(
		g.map((h) => h.key),
		['u1|2026-06-11', 'u1|2026-06-10']
	);
});

test('groupHighlights: two people on one day stay two rows, ordered by newest award', () => {
	const g = groupHighlights(
		[award('b1', 'u1', '2026-06-10T08:00:00Z'), award('b2', 'u2', '2026-06-10T09:00:00Z')],
		utcDay
	);
	assert.deepEqual(
		g.map((h) => h.authorId),
		['u2', 'u1']
	);
});

test('groupHighlights: the day is the one the key function names', () => {
	// 23:30 UTC on the 10th is the 11th at UTC+1.
	const plusOne = (iso: string) => new Date(Date.parse(iso) + 3600_000).toISOString().slice(0, 10);
	const g = groupHighlights(
		[award('b1', 'u1', '2026-06-10T23:30:00Z'), award('b2', 'u1', '2026-06-11T08:00:00Z')],
		plusOne
	);
	assert.equal(g.length, 1);
	assert.equal(g[0].awards.length, 2);
});

test('groupHighlights: an award read twice counts once', () => {
	const a = award('b1', 'u1', '2026-06-10T08:00:00Z');
	const g = groupHighlights([a, a, award('b2', 'u1', '2026-06-10T09:00:00Z')], utcDay);
	assert.equal(g[0].awards.length, 2);
});

test('groupHighlights: an equal instant orders by id, descending', () => {
	const g = groupHighlights(
		[award('a', 'u1', '2026-06-10T08:00:00Z'), award('c', 'u1', '2026-06-10T08:00:00Z')],
		utcDay
	);
	assert.deepEqual(
		g[0].awards.map((x) => x.badge.id),
		['c', 'a']
	);
});

test('interleaveHighlights: highlights sit between entries by time', () => {
	const hs = groupHighlights(
		[award('b1', 'u1', '2026-06-10T12:00:00Z'), award('b2', 'u2', '2026-06-12T12:00:00Z')],
		utcDay
	);
	const rows = interleaveHighlights(
		[entry('r1', '2026-06-13T07:00:00Z'), entry('r2', '2026-06-11T07:00:00Z'), entry('r3', '2026-06-09T07:00:00Z')],
		at,
		hs,
		true
	);
	assert.deepEqual(
		rows.map((r) => (r.kind === 'entry' ? r.entry.id : r.highlight.key)),
		['r1', 'u2|2026-06-12', 'r2', 'u1|2026-06-10', 'r3']
	);
});

test('interleaveHighlights: one older than the last entry waits while more activity can load', () => {
	const hs = groupHighlights([award('b1', 'u1', '2026-06-01T12:00:00Z')], utcDay);
	const rows = interleaveHighlights([entry('r1', '2026-06-10T07:00:00Z')], at, hs, false);
	assert.deepEqual(
		rows.map((r) => r.kind),
		['entry']
	);
});

test('interleaveHighlights: once the activity has run out, older highlights trail it', () => {
	const hs = groupHighlights([award('b1', 'u1', '2026-06-01T12:00:00Z')], utcDay);
	const rows = interleaveHighlights([entry('r1', '2026-06-10T07:00:00Z')], at, hs, true);
	assert.deepEqual(
		rows.map((r) => r.kind),
		['entry', 'highlight']
	);
});

test('interleaveHighlights: no activity at all still shows the highlights', () => {
	const hs = groupHighlights([award('b1', 'u1', '2026-06-01T12:00:00Z')], utcDay);
	const rows = interleaveHighlights([], at, hs, true);
	assert.equal(rows.length, 1);
	assert.equal(rows[0].kind, 'highlight');
});

test('interleaveHighlights: nothing while the first activity page has not loaded', () => {
	const hs = groupHighlights([award('b1', 'u1', '2026-06-01T12:00:00Z')], utcDay);
	assert.deepEqual(interleaveHighlights([], at, hs, false), []);
});

test('interleaveHighlights: at an equal instant the activity entry comes first', () => {
	const hs = groupHighlights([award('b1', 'u1', '2026-06-10T07:00:00Z')], utcDay);
	const rows = interleaveHighlights([entry('r1', '2026-06-10T07:00:00Z')], at, hs, false);
	assert.deepEqual(
		rows.map((r) => r.kind),
		['entry', 'highlight']
	);
});

test('interleaveHighlights: no highlights leaves the entries untouched', () => {
	const rows = interleaveHighlights([entry('r1', '2026-06-10T07:00:00Z')], at, [], false);
	assert.deepEqual(rows, [{ kind: 'entry', entry: entry('r1', '2026-06-10T07:00:00Z') }]);
});

test('needsMoreHighlights: an unread stream needs its first page', () => {
	assert.equal(
		needsMoreHighlights({ oldestAwardAt: null, awardsExhausted: false, oldestEntryAt: null, feedExhausted: false }),
		true
	);
});

test('needsMoreHighlights: an exhausted stream never does', () => {
	assert.equal(
		needsMoreHighlights({ oldestAwardAt: null, awardsExhausted: true, oldestEntryAt: null, feedExhausted: true }),
		false
	);
});

test('needsMoreHighlights: awards reaching no further back than the activity read on', () => {
	assert.equal(
		needsMoreHighlights({
			oldestAwardAt: '2026-06-10T00:00:00Z',
			awardsExhausted: false,
			oldestEntryAt: '2026-06-05T00:00:00Z',
			feedExhausted: false,
		}),
		true
	);
});

test('needsMoreHighlights: awards reaching past the activity wait for it', () => {
	assert.equal(
		needsMoreHighlights({
			oldestAwardAt: '2026-06-01T00:00:00Z',
			awardsExhausted: false,
			oldestEntryAt: '2026-06-05T00:00:00Z',
			feedExhausted: false,
		}),
		false
	);
});

test('needsMoreHighlights: once the activity has run out the awards read to their end', () => {
	assert.equal(
		needsMoreHighlights({
			oldestAwardAt: '2026-06-01T00:00:00Z',
			awardsExhausted: false,
			oldestEntryAt: '2026-06-05T00:00:00Z',
			feedExhausted: true,
		}),
		true
	);
});

test('highlightsShowFor: only the All chip shows highlights', () => {
	assert.equal(highlightsShowFor('all'), true);
	for (const f of ['run', 'walk', 'cycle', 'hike', 'lift']) assert.equal(highlightsShowFor(f), false);
});
