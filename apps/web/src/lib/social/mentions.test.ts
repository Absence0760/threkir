import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	activeMentionQuery,
	insertMention,
	MAX_MENTIONS_PER_COMMENT,
	parseMentionHandles,
	splitMentions,
} from './mentions';

test('parseMentionHandles: lowercases, de-duplicates and keeps first-seen order', () => {
	assert.deepEqual(parseMentionHandles('hi @Alice and @bob_1, then @ALICE again'), ['alice', 'bob_1']);
});

test('parseMentionHandles: an email address mentions nobody', () => {
	assert.deepEqual(parseMentionHandles('mail me@example.com'), []);
});

test('parseMentionHandles: too short, doubled @ and glued handles are not mentions', () => {
	assert.deepEqual(parseMentionHandles('@al @@dave @abc@def'), ['abc']);
});

test('parseMentionHandles: a 31-character run is not truncated to a handle', () => {
	assert.deepEqual(parseMentionHandles(`@${'x'.repeat(31)} @${'y'.repeat(30)}`), ['y'.repeat(30)]);
});

test('parseMentionHandles: punctuation around a handle is fine', () => {
	assert.deepEqual(parseMentionHandles('(@carol), @dan! @erin.'), ['carol', 'dan', 'erin']);
});

test('parseMentionHandles: caps at ten handles, matching the server', () => {
	const body = Array.from({ length: 12 }, (_, i) => `@user${i}`).join(' ');
	assert.equal(parseMentionHandles(body).length, MAX_MENTIONS_PER_COMMENT);
	assert.equal(MAX_MENTIONS_PER_COMMENT, 10);
});

test('splitMentions: cuts text and mentions in order and keeps the typed spelling', () => {
	assert.deepEqual(splitMentions('go @Ana, go'), [
		{ kind: 'text', text: 'go ' },
		{ kind: 'mention', text: '@Ana', handle: 'ana' },
		{ kind: 'text', text: ', go' },
	]);
});

test('splitMentions: a body with no mention is one text segment, an empty body none', () => {
	assert.deepEqual(splitMentions('no one here'), [{ kind: 'text', text: 'no one here' }]);
	assert.deepEqual(splitMentions(''), []);
});

test('activeMentionQuery: the token under the caret, including a bare @', () => {
	assert.deepEqual(activeMentionQuery('hey @Ca', 7), { start: 4, query: 'ca' });
	assert.deepEqual(activeMentionQuery('hey @', 5), { start: 4, query: '' });
});

test('activeMentionQuery: none after a space, inside an email, or past the caret', () => {
	assert.equal(activeMentionQuery('hey @ca ', 8), null);
	assert.equal(activeMentionQuery('me@exa', 6), null);
	assert.equal(activeMentionQuery('hey @ca', 3), null);
});

test('insertMention: replaces the typed prefix and leaves one space after', () => {
	assert.deepEqual(insertMention('hey @ca', 4, 7, 'carol'), { text: 'hey @carol ', caret: 11 });
	assert.deepEqual(insertMention('hey @ca there', 4, 7, 'carol'), {
		text: 'hey @carol there',
		caret: 11,
	});
});

test('insertMention: swallows the rest of a half-typed handle after the caret', () => {
	assert.deepEqual(insertMention('@caxx', 0, 3, 'carol'), { text: '@carol ', caret: 7 });
});
