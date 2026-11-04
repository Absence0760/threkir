import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
	conversationWriteKey,
	overlayConversationWrites,
	revertConversationFlag,
	settledConversationWrites,
	type ConversationWrite,
} from './dm_conversation_writes.ts';

type Row = { conversationId: string; muted: boolean; archived: boolean; lastBody: string };

const row = (conversationId: string, lastBody: string, muted = false, archived = false): Row => ({
	conversationId,
	muted,
	archived,
	lastBody,
});

test('a write in flight wins over every read that lands during it', () => {
	const write: ConversationWrite = { conversationId: 'a', flag: 'muted', value: true, at: Infinity };
	const polled = [row('a', 'new reply'), row('b', 'hi')];
	const out = overlayConversationWrites(polled, [write], 5_000);
	assert.equal(out[0].muted, true);
	assert.equal(out[0].lastBody, 'new reply');
	assert.deepEqual(out[1], polled[1]);
});

test('a read started before the write landed keeps the write; one started after takes the server', () => {
	const write: ConversationWrite = { conversationId: 'a', flag: 'archived', value: true, at: 1_000 };
	assert.equal(overlayConversationWrites([row('a', 'x')], [write], 999)[0].archived, true);
	assert.equal(overlayConversationWrites([row('a', 'x')], [write], 1_000)[0].archived, true);
	assert.equal(overlayConversationWrites([row('a', 'x', false, false)], [write], 1_001)[0].archived, false);
});

test('only the writes a read already carries are settled', () => {
	const landed: ConversationWrite = { conversationId: 'a', flag: 'muted', value: true, at: 1_000 };
	const pending: ConversationWrite = { conversationId: 'b', flag: 'muted', value: true, at: Infinity };
	assert.deepEqual(settledConversationWrites([landed, pending], 1_001), [landed]);
	assert.deepEqual(settledConversationWrites([landed, pending], 1_000), []);
});

test('a refused write reverts its one field and keeps what a poll brought in during it', () => {
	// The runner mutes `a`; the list is patched at once.
	let threads = [row('a', 'old'), row('b', 'old')];
	const write: ConversationWrite = { conversationId: 'a', flag: 'muted', value: true, at: Infinity };
	threads = overlayConversationWrites(threads, [write], 0);
	assert.equal(threads[0].muted, true);

	// A poll lands mid-write with a new message in each conversation and `b`
	// archived from another device.
	threads = overlayConversationWrites([row('a', 'reply'), row('b', 'reply', false, true)], [write], 10);
	assert.equal(threads[0].muted, true);

	// The write is refused: the mute comes off, the poll's rows stay.
	threads = revertConversationFlag(threads, 'a', 'muted', false);
	assert.deepEqual(threads, [row('a', 'reply'), row('b', 'reply', false, true)]);
});

test('a revert leaves the other flag of the same conversation alone', () => {
	const out = revertConversationFlag([row('a', 'x', true, true)], 'a', 'archived', false);
	assert.deepEqual(out, [row('a', 'x', true, false)]);
});

test('two flags of one conversation are tracked apart', () => {
	assert.notEqual(conversationWriteKey('a', 'muted'), conversationWriteKey('a', 'archived'));
	const writes: ConversationWrite[] = [
		{ conversationId: 'a', flag: 'muted', value: true, at: Infinity },
		{ conversationId: 'a', flag: 'archived', value: true, at: Infinity },
	];
	const out = overlayConversationWrites([row('a', 'x')], writes, 0);
	assert.equal(out[0].muted, true);
	assert.equal(out[0].archived, true);
});

test('the inbox store reverts one field on a refused write, never a snapshot of the list', () => {
	const src = readFileSync(new URL('../stores/messages_inbox.svelte.ts', import.meta.url), 'utf8');
	const body = src.slice(src.indexOf('async #setFlag('), src.indexOf('/// Deletes a conversation for the runner'));
	assert.match(body, /revertConversationFlag\(/);
	assert.doesNotMatch(body, /this\.threads = before/);
	assert.match(src, /#apply\(rows[^)]*\)\s*\{[\s\S]*?overlayConversationWrites\(/);
});
