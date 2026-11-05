import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
	confirmedFlagValue,
	conversationWriteKey,
	dropRefusedWrite,
	overlayConversationWrites,
	restoreHiddenConversation,
	revertConversationFlag,
	settledConversationWrites,
	settledHides,
	settleLandedWrite,
	withoutHiddenConversations,
	type ConversationWrite,
} from './dm_conversation_writes.ts';

type Row = { conversationId: string; muted: boolean; archived: boolean; markedUnread?: boolean; lastBody: string };

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

test('a mark-unread write rides beside a mute on the same row and leaves it alone', () => {
	const mark: ConversationWrite = { conversationId: 'a', flag: 'markedUnread', value: true, at: Infinity };
	const mute: ConversationWrite = { conversationId: 'a', flag: 'muted', value: true, at: 1_000 };
	const [out] = overlayConversationWrites([row('a', 'x')], [mark, mute], 2_000);
	assert.equal(out.markedUnread, true);
	assert.equal(out.muted, false);
	const [reverted] = revertConversationFlag([{ ...row('a', 'x'), markedUnread: true }], 'a', 'markedUnread', false);
	assert.equal(reverted.markedUnread, false);
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
	// Undo re-reads the list every time, so a message that arrived during the
	// window updates the restored row's preview and unread count.
	const restore = hide.slice(hide.indexOf('restore:'), hide.lastIndexOf('onCommitError:'));
	assert.match(restore, /if \(restored\) this\.threads = restored;\s*void this\.refreshThreads\(\);/);
	assert.match(restore, /if \(this\.#userId !== userId\) return;/);
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

/// The inbox's list-read path (#apply in messages_inbox.svelte.ts) with a
/// controllable clock and list reads that resolve when the test says so.
function inboxHarness(initial: string[]) {
	let now = 0;
	const hiddenAt = new Map<string, number>();
	let threads = initial.map((id) => listed(id, '2026-11-01T00:00:00Z'));
	const reads: { startedAt: number; resolve: (rows: Listed[]) => void; done: Promise<void> }[] = [];
	return {
		tick(ms = 1) {
			now += ms;
		},
		get threads() {
			return threads.map((t) => t.conversationId);
		},
		get markers() {
			return new Map(hiddenAt);
		},
		startRead() {
			const startedAt = now;
			let resolve!: (rows: Listed[]) => void;
			const done = new Promise<Listed[]>((r) => (resolve = r)).then((rows) => {
				threads = withoutHiddenConversations(rows, hiddenAt, startedAt);
				for (const id of settledHides(hiddenAt, startedAt)) hiddenAt.delete(id);
			});
			const read = { startedAt, resolve, done };
			reads.push(read);
			return read;
		},
		hide(id: string) {
			hiddenAt.set(id, Infinity);
			threads = threads.filter((t) => t.conversationId !== id);
		},
		commit(id: string) {
			hiddenAt.set(id, now);
		},
		undo(id: string) {
			hiddenAt.delete(id);
		},
	};
}

const server = (...ids: string[]) => ids.map((id) => listed(id, '2026-11-01T00:00:00Z'));

test('a poll that started before the delete landed and returns after the window closed keeps the row gone', async () => {
	const inbox = inboxHarness(['a', 'b']);
	inbox.hide('b');
	inbox.tick(1_000);
	const poll = inbox.startRead();
	inbox.tick(4_000);
	inbox.commit('b'); // the server hides it; the pending flag clears
	inbox.tick(500);
	poll.resolve(server('a', 'b')); // answers with the list from before the delete
	await poll.done;
	assert.deepEqual(inbox.threads, ['a']);
	assert.equal(inbox.markers.has('b'), true);
});

test('a poll started after the delete landed applies as the server says and expires the marker', async () => {
	const inbox = inboxHarness(['a', 'b']);
	inbox.hide('b');
	inbox.tick(5_000);
	inbox.commit('b');
	inbox.tick(1);
	const poll = inbox.startRead();
	poll.resolve(server('a', 'c'));
	await poll.done;
	assert.deepEqual(inbox.threads, ['a', 'c']);
	assert.equal(inbox.markers.size, 0);
});

test('after the marker expires a newer message brings the deleted conversation back', async () => {
	const inbox = inboxHarness(['a', 'b']);
	inbox.hide('b');
	inbox.commit('b');
	inbox.tick(1);
	const first = inbox.startRead();
	first.resolve(server('a'));
	await first.done;
	assert.equal(inbox.markers.size, 0);
	inbox.tick(30_000);
	const next = inbox.startRead();
	next.resolve(server('b', 'a'));
	await next.done;
	assert.deepEqual(inbox.threads, ['b', 'a']);
});

test('a read applied during the window leaves the row out and keeps the marker', async () => {
	const inbox = inboxHarness(['a', 'b']);
	inbox.hide('b');
	inbox.tick(1_000);
	const poll = inbox.startRead();
	poll.resolve(server('a', 'b'));
	await poll.done;
	assert.deepEqual(inbox.threads, ['a']);
	assert.equal(inbox.markers.get('b'), Infinity);
});

test('a read started in the same millisecond the delete landed does not expire the marker', () => {
	const hiddenAt = new Map([['b', 2_000]]);
	assert.deepEqual(withoutHiddenConversations(server('a', 'b'), hiddenAt, 2_000).map((r) => r.conversationId), ['a']);
	assert.deepEqual(settledHides(hiddenAt, 2_000), []);
	assert.deepEqual(settledHides(hiddenAt, 2_001), ['b']);
});

test('undo drops the marker, so the next read lists the conversation', async () => {
	const inbox = inboxHarness(['a', 'b']);
	inbox.hide('b');
	const poll = inbox.startRead();
	inbox.undo('b');
	poll.resolve(server('a', 'b'));
	await poll.done;
	assert.deepEqual(inbox.threads, ['a', 'b']);
});

test('the inbox store holds a delete against reads that started before it landed', () => {
	const src = readFileSync(new URL('../stores/messages_inbox.svelte.ts', import.meta.url), 'utf8');
	const apply = src.slice(src.indexOf('\t#apply(rows'), src.indexOf('\tasync loadThreads('));
	assert.match(apply, /withoutHiddenConversations\(rows, this\.#hiddenAt, startedAt\)/);
	assert.match(apply, /settledHides\(this\.#hiddenAt, startedAt\)/);
	assert.doesNotMatch(apply, /dmPendingHides/);
	const hide = src.slice(src.indexOf('\thide(conversationId'), src.indexOf('\tmarkRead('));
	assert.match(hide, /this\.#hiddenAt\.set\(conversationId, Infinity\)/);
	const commit = hide.slice(hide.indexOf('commit:'), hide.indexOf('restore:'));
	assert.match(commit, /await hideDmConversation\(conversationId, opts\.throughMessageId\);\s*if \(this\.#userId === userId\) this\.#hiddenAt\.set\(conversationId, performance\.now\(\)\)/);
	assert.match(hide.slice(hide.indexOf('restore:')), /this\.#hiddenAt\.delete\(conversationId\)/);
	const bind = src.slice(src.indexOf('\tbind(userId'), src.indexOf('\t#apply(rows'));
	assert.match(bind, /this\.#hiddenAt\.clear\(\)/);
});

// Reason: a list read carries the session it started under. One that lands
// after the inbox was bound to another account (a sign-out or a sign-in in
// another tab) would show the previous account's conversations to the next.
test('the inbox store applies a list read only to the account it was read for', () => {
	const src = readFileSync(new URL('../stores/messages_inbox.svelte.ts', import.meta.url), 'utf8');
	assert.match(src, /#apply\(rows: DmThread\[\], startedAt: number, userId: string \| null\) \{\s*if \(userId !== this\.#userId\) return;/);
	const reads = src.slice(src.indexOf('\tasync loadThreads('), src.indexOf('\t#patch('));
	const calls = reads.match(/this\.#apply\([^)]*\)\)?[^;]*;/g) ?? [];
	assert.equal(calls.length, 3);
	for (const call of calls) assert.match(call, /this\.#apply\(await fetchDmThreads\(\), startedAt, userId\)/);
	assert.equal(reads.match(/const userId = this\.#userId;\s*const startedAt/g)?.length, 3);
});

// Reason: every marker here (#hiddenAt, #writes, #markedReadAt) is compared
// with when a list read started. On the wall clock a step backwards (an NTP
// correction after sleep, a manual change) leaves each marker newer than every
// read for as long as the step: a deleted conversation a new message brought
// back stays hidden, a write overrides what the server says, and a thread
// opened before the step shows no unread for new messages.
test('the inbox store times its reads and markers on the monotonic clock', () => {
	const src = readFileSync(new URL('../stores/messages_inbox.svelte.ts', import.meta.url), 'utf8');
	assert.doesNotMatch(src, /Date\.now\(\)/);
	assert.equal(src.match(/const startedAt = performance\.now\(\);/g)?.length, 3);
});

test('the badge applies only its newest read, so a read from before a delete cannot land after it', () => {
	const src = readFileSync(new URL('../stores/dm_unread.svelte.ts', import.meta.url), 'utf8');
	assert.match(src, /#reader = new DmBadgeReader\(/);
	assert.match(src, /async refresh\(\) \{\s*await this\.#reader\.refresh\(\);/);
	assert.match(src, /clear\(\) \{\s*this\.#reader\.bind\(null\);/);
	const inbox = readFileSync(new URL('../stores/messages_inbox.svelte.ts', import.meta.url), 'utf8');
	const commit = inbox.slice(inbox.indexOf('commit: async'), inbox.indexOf('restore:'));
	assert.match(commit, /dmUnreadStore\.forget\(conversationId\);[\s\S]*dmPendingHides\.delete\(conversationId\);[\s\S]*void dmUnreadStore\.refresh\(\);/);
});

/// #setFlag's bookkeeping in messages_inbox.svelte.ts, driven write by write.
function flagHarness(serverMuted: boolean) {
	const writes = new Map<string, ConversationWrite>();
	let threads = [row('a', 'x', serverMuted)];
	return {
		writes,
		get muted() {
			return threads[0].muted;
		},
		start(value: boolean): ConversationWrite {
			const key = conversationWriteKey('a', 'muted');
			const w: ConversationWrite = {
				conversationId: 'a',
				flag: 'muted',
				value,
				at: Infinity,
				prior: confirmedFlagValue(writes.get(key), threads[0].muted),
			};
			writes.set(key, w);
			threads = revertConversationFlag(threads, 'a', 'muted', value);
			return w;
		},
		refuse(w: ConversationWrite) {
			if (dropRefusedWrite(writes, w) && w.prior !== undefined) {
				threads = revertConversationFlag(threads, 'a', 'muted', w.prior);
			}
		},
		land(w: ConversationWrite, at: number) {
			settleLandedWrite(writes, w, at);
		},
	};
}

test('two refused writes to one flag put back what the server held, not the first write', () => {
	const inbox = flagHarness(false);
	const mute = inbox.start(true);
	const unmute = inbox.start(false);
	assert.equal(unmute.prior, false);
	inbox.refuse(mute);
	assert.equal(inbox.muted, false);
	inbox.refuse(unmute);
	assert.equal(inbox.muted, false);
	assert.equal(inbox.writes.size, 0);
});

test('two refused writes in the other order still end on the server value', () => {
	const inbox = flagHarness(false);
	const mute = inbox.start(true);
	const unmute = inbox.start(false);
	inbox.refuse(unmute);
	assert.equal(inbox.muted, false);
	inbox.refuse(mute);
	assert.equal(inbox.muted, false);
});

test('an earlier write that lands becomes what a later refused write reverts to', () => {
	const inbox = flagHarness(false);
	const mute = inbox.start(true);
	const unmute = inbox.start(false);
	inbox.land(mute, 1_000);
	assert.equal(unmute.prior, true);
	assert.equal(inbox.writes.get(conversationWriteKey('a', 'muted')), unmute);
	inbox.refuse(unmute);
	assert.equal(inbox.muted, true);
});

test('a write after one that landed reverts to the landed value', () => {
	const inbox = flagHarness(false);
	const mute = inbox.start(true);
	inbox.land(mute, 1_000);
	assert.equal(inbox.writes.get(conversationWriteKey('a', 'muted'))?.at, 1_000);
	const unmute = inbox.start(false);
	assert.equal(unmute.prior, true);
	inbox.refuse(unmute);
	assert.equal(inbox.muted, true);
});

test('the inbox store reverts to the confirmed value, never one read off the optimistic list', () => {
	const src = readFileSync(new URL('../stores/messages_inbox.svelte.ts', import.meta.url), 'utf8');
	const body = src.slice(src.indexOf('async #setFlag('), src.indexOf('/// Deletes a conversation for the runner'));
	assert.match(body, /prior: confirmedFlagValue\(this\.#writes\.get\(key\), listed\)/);
	assert.match(body, /revertConversationFlag\(this\.threads, conversationId, flag, pending\.prior\)/);
	assert.match(body, /settleLandedWrite\(this\.#writes, pending, performance\.now\(\)\)/);
});
