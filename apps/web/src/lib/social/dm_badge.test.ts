import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { unreadDmBadgeCountExcept, type DmBadgeState } from './dm_badge.ts';

const state = (conversationId: string, unread: number, muted = false, archived = false): DmBadgeState => ({
	conversationId,
	unread,
	muted,
	archived,
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
