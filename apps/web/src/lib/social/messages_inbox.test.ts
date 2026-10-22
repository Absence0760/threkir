import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	COACH_PREVIEW_MAX,
	MESSAGES_COACH_ROW_KEY,
	coachInboxPreview,
	inboxEntries,
	parseCoachInboxPlacement
} from './messages_inbox';

const thread = (id: string, lastAt: string) => ({ id, lastAt });
const ids = (entries: ReturnType<typeof inboxEntries<{ id: string; lastAt: string }>>) =>
	entries.map((e) => (e.kind === 'coach' ? 'coach' : e.thread.id));

const threads = [
	thread('a', '2026-10-21T09:00:00+00:00'),
	thread('b', '2026-10-20T09:00:00+00:00'),
	thread('c', '2026-10-19T09:00:00+00:00')
];

test('the settings key is the one the registry names', () => {
	assert.equal(MESSAGES_COACH_ROW_KEY, 'messages_coach_row');
});

test('an absent or unknown placement reads as pinned', () => {
	assert.equal(parseCoachInboxPlacement(undefined), 'pinned');
	assert.equal(parseCoachInboxPlacement(null), 'pinned');
	assert.equal(parseCoachInboxPlacement('Hidden'), 'pinned');
	assert.equal(parseCoachInboxPlacement(true), 'pinned');
	assert.equal(parseCoachInboxPlacement('pinned'), 'pinned');
	assert.equal(parseCoachInboxPlacement('listed'), 'listed');
	assert.equal(parseCoachInboxPlacement('hidden'), 'hidden');
});

test('with no Coach row the inbox is the conversations in their order', () => {
	assert.deepEqual(ids(inboxEntries(threads, null)), ['a', 'b', 'c']);
});

test('a hidden Coach is left out', () => {
	const out = inboxEntries(threads, { placement: 'hidden', lastAt: '2026-10-22T00:00:00Z' });
	assert.deepEqual(ids(out), ['a', 'b', 'c']);
});

test('a pinned Coach sits above every conversation, however old its last message', () => {
	assert.deepEqual(
		ids(inboxEntries(threads, { placement: 'pinned', lastAt: '2020-01-01T00:00:00Z' })),
		['coach', 'a', 'b', 'c']
	);
	assert.deepEqual(ids(inboxEntries(threads, { placement: 'pinned', lastAt: null })), [
		'coach',
		'a',
		'b',
		'c'
	]);
});

test('a pinned Coach is the only row of an empty inbox', () => {
	assert.deepEqual(ids(inboxEntries([], { placement: 'pinned', lastAt: null })), ['coach']);
});

test('a listed Coach is filed by its latest message', () => {
	assert.deepEqual(
		ids(inboxEntries(threads, { placement: 'listed', lastAt: '2026-10-20T12:00:00+00:00' })),
		['a', 'coach', 'b', 'c']
	);
	assert.deepEqual(
		ids(inboxEntries(threads, { placement: 'listed', lastAt: '2026-10-22T00:00:00+00:00' })),
		['coach', 'a', 'b', 'c']
	);
	assert.deepEqual(
		ids(inboxEntries(threads, { placement: 'listed', lastAt: '2026-10-01T00:00:00+00:00' })),
		['a', 'b', 'c', 'coach']
	);
});

test('a listed Coach tied with a conversation goes after it', () => {
	assert.deepEqual(
		ids(inboxEntries(threads, { placement: 'listed', lastAt: '2026-10-20T09:00:00Z' })),
		['a', 'b', 'coach', 'c']
	);
	// The same millisecond is a tie, whatever the microseconds say.
	assert.deepEqual(
		ids(
			inboxEntries([thread('x', '2026-10-20T09:00:00.123456Z')], {
				placement: 'listed',
				lastAt: '2026-10-20T09:00:00.123900Z'
			})
		),
		['x', 'coach']
	);
	// An unreadable stamp sorts as oldest.
	assert.deepEqual(
		ids(inboxEntries([thread('x', 'not a date')], { placement: 'listed', lastAt: '2020-01-01T00:00:00Z' })),
		['coach', 'x']
	);
});

test('a listed Coach with no message goes last', () => {
	assert.deepEqual(ids(inboxEntries(threads, { placement: 'listed', lastAt: null })), [
		'a',
		'b',
		'c',
		'coach'
	]);
});

test('the preview drops markdown and keeps the words', () => {
	assert.equal(
		coachInboxPreview('## Today\n\n- **Easy** 6 km at `5:40/km`\n- see [the plan](/plans/x)\n> rest'),
		'Today Easy 6 km at 5:40/km see the plan rest'
	);
	assert.equal(coachInboxPreview('1. warm up\n2) strides'), 'warm up strides');
	assert.equal(coachInboxPreview('```js\ncode()\n```'), 'code()');
	assert.equal(coachInboxPreview('keep snake_case and 3*4'), 'keep snake_case and 34');
	assert.equal(coachInboxPreview('   \n\n  '), '');
	assert.equal(coachInboxPreview('\u0085rest day\u0085'), 'rest day');
});

test('a long preview is cut on a code point with an ellipsis', () => {
	const long = 'x'.repeat(COACH_PREVIEW_MAX + 10);
	const out = coachInboxPreview(long);
	assert.equal(Array.from(out).length, COACH_PREVIEW_MAX);
	assert.ok(out.endsWith('…'));
	const emoji = '\u{1F3C3}'.repeat(COACH_PREVIEW_MAX + 1);
	const cut = coachInboxPreview(emoji);
	assert.equal(Array.from(cut).length, COACH_PREVIEW_MAX);
	assert.equal(Array.from(cut)[0], '\u{1F3C3}');
	assert.equal(coachInboxPreview('x'.repeat(COACH_PREVIEW_MAX)), 'x'.repeat(COACH_PREVIEW_MAX));
});
