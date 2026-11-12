import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { DmBadgeReader, unreadDmBadgeCountExcept, type DmBadgeState } from './dm_badge.ts';

const state = (conversationId: string, unread: number, muted = false, archived = false): DmBadgeState => ({
	conversationId,
	unread,
	muted,
	archived,
	request: false,
});

test('a conversation whose delete is pending leaves the badge', () => {
	const states = [state('a', 3), state('b', 2)];
	assert.equal(unreadDmBadgeCountExcept(states, new Set()), 5);
	assert.equal(unreadDmBadgeCountExcept(states, new Set(['a'])), 2);
	assert.equal(unreadDmBadgeCountExcept(states, new Set(['a', 'b'])), 0);
});

test('the pending set changes nothing else about the badge rule', () => {
	const states = [state('a', 3, true), state('b', 2, false, true), state('c', 4)];
	assert.equal(unreadDmBadgeCountExcept(states, new Set(['missing'])), 4);
});

const read = (rel: string) => readFileSync(new URL(rel, import.meta.url), 'utf8');

test('the badge store counts from held states minus the pending deletes, not a fetched number', () => {
	const src = read('../stores/dm_unread.svelte.ts');
	assert.match(src, /\$derived\(unreadDmBadgeCountExcept\(this\.#states, dmPendingHides\)\)/);
	assert.match(src, /fetch: \(\) => fetchDmBadgeStates\(\)/);
});

test('the inbox shares the pending set with the badge and re-reads it on undo and commit only', () => {
	const src = read('../stores/messages_inbox.svelte.ts');
	const hide = src.slice(src.indexOf('\thide(conversationId'), src.indexOf('\tmarkRead('));
	assert.match(hide, /dmPendingHides\.add\(conversationId\)/);
	const beforeDefer = hide.slice(0, hide.indexOf('deferDestructive('));
	assert.doesNotMatch(beforeDefer, /dmUnreadStore\.refresh\(\)/);
	const commit = hide.slice(hide.indexOf('commit:'), hide.indexOf('restore:'));
	assert.match(commit, /dmUnreadStore\.forget\(conversationId\)/);
	assert.match(commit, /dmUnreadStore\.refresh\(\)/);
	const restore = hide.slice(hide.indexOf('restore:'), hide.lastIndexOf('onCommitError:'));
	assert.match(restore, /dmPendingHides\.delete\(conversationId\)/);
	assert.match(restore, /dmUnreadStore\.refresh\(\)/);
	assert.doesNotMatch(src, /#pendingHidden/);
});

/// A reader whose every fetch hangs until the test resolves it.
function controlledReader() {
	const fetches: { resolve: (s: DmBadgeState[]) => void; reject: (e: unknown) => void }[] = [];
	const applied: DmBadgeState[][] = [];
	const errors: unknown[] = [];
	const reader = new DmBadgeReader({
		fetch: () =>
			new Promise<DmBadgeState[]>((resolve, reject) => {
				fetches.push({ resolve, reject });
			}),
		apply: (states) => applied.push(states),
		onError: (e) => errors.push(e),
	});
	return { reader, fetches, applied, errors };
}

// Reason: the sign-out's own undo commit starts a badge read under the
// signing-out account; it lands after the layout cleared the badge and would
// show that account's count to a signed-out reader.
test('a badge read that lands after sign-out is dropped', async () => {
	const { reader, fetches, applied } = controlledReader();
	reader.bind('a');
	const read = reader.refresh();
	reader.bind(null);
	fetches[0].resolve([state('x', 4)]);
	await read;
	assert.deepEqual(applied, []);
});

test('a badge read started under one account is not shown to the next', async () => {
	const { reader, fetches, applied } = controlledReader();
	reader.bind('a');
	const readA = reader.refresh();
	reader.bind('b');
	fetches[0].resolve([state('x', 4)]);
	await readA;
	assert.deepEqual(applied, []);
	const readB = reader.refresh();
	fetches[1].resolve([state('y', 1)]);
	await readB;
	assert.deepEqual(applied, [[state('y', 1)]]);
});

test('a badge read for the bound account is applied', async () => {
	const { reader, fetches, applied } = controlledReader();
	assert.equal(reader.bind('a'), true);
	assert.equal(reader.bind('a'), false);
	const read = reader.refresh();
	fetches[0].resolve([state('x', 2)]);
	await read;
	assert.deepEqual(applied, [[state('x', 2)]]);
});

test('signed out, the badge does not read at all', async () => {
	const { reader, fetches } = controlledReader();
	await reader.refresh();
	reader.bind('a');
	reader.bind(null);
	await reader.refresh();
	assert.equal(fetches.length, 0);
});

test('the layout binds the badge to the signed-in account before reading', () => {
	const layout = readFileSync(new URL('../../routes/+layout.svelte', import.meta.url), 'utf8');
	assert.match(layout, /dmUnreadStore\.bind\(uid\);\s*dmUnreadStore\.refresh\(\);/);
});
