import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
	conversationWriteKey,
	dropRefusedWrite,
	overlayConversationWrites,
	restoreHiddenConversation,
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
	assert.match(body, /if \(!dropRefusedWrite\(this\.#writes, pending\)\) throw e;/);
	assert.doesNotMatch(body, /this\.threads = before/);
	assert.match(src, /#apply\(rows[^)]*\)\s*\{[\s\S]*?overlayConversationWrites\(/);
});

type Listed = { conversationId: string; lastAt: string; lastBody: string };
const listed = (conversationId: string, lastAt: string, lastBody = 'x'): Listed => ({ conversationId, lastAt, lastBody });

test('an undone delete puts back its one row by latest message and keeps what a poll brought in', () => {
	const hidden = listed('b', '2026-11-02T10:00:00Z', 'old');
	// During the window a poll brought a reply into `a` and a new conversation `d`.
	const polled = [listed('d', '2026-11-04T09:00:00Z'), listed('a', '2026-11-03T08:00:00Z', 'reply'), listed('c', '2026-11-01T00:00:00Z')];
	assert.deepEqual(restoreHiddenConversation(polled, hidden), [polled[0], polled[1], hidden, polled[2]]);
	assert.deepEqual(restoreHiddenConversation([listed('a', '2026-11-01T00:00:00Z')], hidden)?.map((r) => r.conversationId), ['b', 'a']);
	assert.deepEqual(restoreHiddenConversation([], hidden), [hidden]);
});

test('a restore does not duplicate a row a read already brought back', () => {
	const fresh = listed('b', '2026-11-04T00:00:00Z', 'newer');
	const out = restoreHiddenConversation([fresh], listed('b', '2026-11-02T00:00:00Z', 'old'));
	assert.deepEqual(out, [fresh]);
});

test('a row the list never held asks for a list read', () => {
	assert.equal(restoreHiddenConversation([listed('a', '2026-11-01T00:00:00Z')], undefined), null);
});

test('the inbox store restores one hidden row on undo, never a snapshot of the list', () => {
	const src = readFileSync(new URL('../stores/messages_inbox.svelte.ts', import.meta.url), 'utf8');
	const hide = src.slice(src.indexOf('\thide(conversationId'), src.indexOf('\tmarkRead('));
	assert.match(hide, /restoreHiddenConversation\(this\.threads, hidden\)/);
	assert.match(hide, /else void this\.refreshThreads\(\)/);
	assert.doesNotMatch(hide, /this\.threads = before/);
	assert.doesNotMatch(hide, /const before = this\.threads/);
});

test('a refused write a later write superseded reverts nothing; the later value stays', () => {
	const key = conversationWriteKey('a', 'muted');
	const writes = new Map<string, ConversationWrite>();
	let threads = [row('a', 'x')];
	// A: mute, in flight.
	const a: ConversationWrite = { conversationId: 'a', flag: 'muted', value: true, at: Infinity };
	writes.set(key, a);
	threads = revertConversationFlag(threads, 'a', 'muted', true);
	// B: unmute, lands.
	const b: ConversationWrite = { conversationId: 'a', flag: 'muted', value: false, at: 2_000 };
	writes.set(key, b);
	threads = revertConversationFlag(threads, 'a', 'muted', false);
	// A is refused: B owns the field, so nothing is dropped or reverted.
	assert.equal(dropRefusedWrite(writes, a), false);
	assert.equal(writes.get(key), b);
	assert.equal(threads[0].muted, false);
	assert.equal(overlayConversationWrites([row('a', 'x', true)], writes.values(), 1_000)[0].muted, false);
});

test('a refused write that is still the latest is dropped and reverted', () => {
	const writes = new Map<string, ConversationWrite>();
	const a: ConversationWrite = { conversationId: 'a', flag: 'archived', value: true, at: Infinity };
	writes.set(conversationWriteKey('a', 'archived'), a);
	assert.equal(dropRefusedWrite(writes, a), true);
	assert.equal(writes.size, 0);
});
