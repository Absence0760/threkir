import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	createUndoQueue,
	undoWindowSFromPref,
	DEFAULT_UNDO_WINDOW_S,
	UNDO_WINDOW_CHOICES_S,
	type PendingUndo,
	type UndoOwner,
	undoOwnerChanged,
} from './undo_queue.js';

/// Deterministic clock + timer pair. `advance` fires every timer whose
/// deadline has passed, in deadline order, so a re-armed timer created
/// mid-advance still lands correctly.
function harness(windowMs = 8000) {
	let clock = 0;
	let nextHandle = 1;
	const timers = new Map<number, { at: number; cb: () => void }>();
	const published: (PendingUndo | null)[] = [];
	let currentWindowMs = windowMs;
	let currentOwner: UndoOwner = 'a';

	const queue = createUndoQueue({
		windowMs: () => currentWindowMs,
		setTimer: (cb, ms) => {
			const handle = nextHandle++;
			timers.set(handle, { at: clock + ms, cb });
			return handle;
		},
		clearTimer: (handle) => {
			timers.delete(handle as number);
		},
		now: () => clock,
		onChange: (pending) => published.push(pending),
		owner: () => currentOwner,
	});

	async function advance(ms: number) {
		const target = clock + ms;
		for (;;) {
			let due: [number, { at: number; cb: () => void }] | null = null;
			for (const entry of timers) {
				if (entry[1].at <= target && (due === null || entry[1].at < due[1].at)) due = entry;
			}
			if (due === null) break;
			clock = due[1].at;
			timers.delete(due[0]);
			due[1].cb();
			// Let the awaited commit() inside flush() settle.
			await Promise.resolve();
			await Promise.resolve();
		}
		clock = target;
	}

	return {
		queue,
		published,
		advance,
		armedTimers: () => timers.size,
		setWindowMs: (ms: number) => {
			currentWindowMs = ms;
		},
		setOwner: (id: UndoOwner) => {
			currentOwner = id;
		},
		tick: (ms: number) => {
			clock += ms;
		},
	};
}

function spy() {
	const calls: unknown[][] = [];
	const fn = (...args: unknown[]) => {
		calls.push(args);
	};
	return { fn, calls, get count() { return calls.length; } };
}

// ---------------------------------------------------------------------------
// The central contract: nothing is destroyed while undo is on offer
// ---------------------------------------------------------------------------

test('defer holds the mutation — commit has not run when the bar appears', () => {
	const h = harness();
	const commit = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: () => {} });
	assert.equal(commit.count, 0);
	assert.equal(h.queue.hasPending(), true);
	assert.deepEqual(h.published.at(-1), { id: 1, message: 'Removed', windowMs: 8000, paused: false });
});

test('undo cancels the pending mutation entirely — commit never runs, restore does', () => {
	const h = harness();
	const commit = spy();
	const restore = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: restore.fn });
	h.queue.undo();
	assert.equal(commit.count, 0);
	assert.equal(restore.count, 1);
	assert.equal(h.queue.hasPending(), false);
	assert.equal(h.published.at(-1), null);
	assert.equal(h.armedTimers(), 0);
});

test('the window elapsing commits, and does NOT restore', async () => {
	const h = harness();
	const commit = spy();
	const restore = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: restore.fn });
	await h.advance(7999);
	assert.equal(commit.count, 0);
	await h.advance(1);
	assert.equal(commit.count, 1);
	assert.equal(restore.count, 0);
	assert.equal(h.queue.hasPending(), false);
});

test('a failed commit restores the caller state and reports the error', async () => {
	const h = harness();
	const restore = spy();
	const onCommitError = spy();
	const boom = new Error('23503');
	h.queue.defer({
		message: 'Removed',
		commit: async () => {
			throw boom;
		},
		restore: restore.fn,
		onCommitError: onCommitError.fn,
	});
	await h.advance(8000);
	assert.equal(restore.count, 1);
	assert.deepEqual(onCommitError.calls, [[boom]]);
});

// Reason: a commit already running when another tab ended the session
// failed with no session, and the queue toasted "couldn't delete" to the
// signed-out reader and restored the row into whatever list was showing.
function heldCommit() {
	let fail!: (e: unknown) => void;
	let succeed!: () => void;
	const running = new Promise<void>((resolve, reject) => {
		fail = reject;
		succeed = resolve;
	});
	return { commit: () => running, fail, succeed };
}

async function settle() {
	for (let i = 0; i < 5; i++) await Promise.resolve();
}

test('a commit that fails after its account signed out is logged, not toasted or restored', async () => {
	const h = harness();
	const restore = spy();
	const onCommitError = spy();
	const held = heldCommit();
	h.queue.defer({ message: 'Removed', commit: held.commit, restore: restore.fn, onCommitError: onCommitError.fn });
	const flushing = h.queue.flush();
	h.setOwner(null);
	const logged: unknown[][] = [];
	const error = console.error;
	console.error = (...args: unknown[]) => logged.push(args);
	try {
		const boom = new Error('no session');
		held.fail(boom);
		await flushing;
		assert.equal(restore.count, 0);
		assert.equal(onCommitError.count, 0);
		assert.equal(logged.length, 1);
		assert.equal(logged[0][1], boom);
	} finally {
		console.error = error;
	}
});

test('a commit that fails after another account signed in leaves that account alone', async () => {
	const h = harness();
	const restore = spy();
	const onCommitError = spy();
	const held = heldCommit();
	h.queue.defer({ message: 'Removed', commit: held.commit, restore: restore.fn, onCommitError: onCommitError.fn });
	await h.advance(8000);
	h.setOwner('b');
	const error = console.error;
	console.error = () => {};
	try {
		held.fail(new Error('JWT expired'));
		await settle();
	} finally {
		console.error = error;
	}
	assert.equal(restore.count, 0);
	assert.equal(onCommitError.count, 0);
});

test('a commit that fails while its account is still signed in still restores and reports', async () => {
	const h = harness();
	const restore = spy();
	const onCommitError = spy();
	const held = heldCommit();
	h.queue.defer({ message: 'Removed', commit: held.commit, restore: restore.fn, onCommitError: onCommitError.fn });
	const flushing = h.queue.flush();
	const boom = new Error('23503');
	held.fail(boom);
	await flushing;
	assert.equal(restore.count, 1);
	assert.deepEqual(onCommitError.calls, [[boom]]);
});

test('a commit that fails while the same account is briefly unknown still restores and reports', async () => {
	// A -> not-known-yet -> A: the profile is reloading for a live session.
	// Nothing says another account is signed in, so the list must not keep
	// claiming a row is gone that the server still holds.
	const h = harness();
	const restore = spy();
	const onCommitError = spy();
	const held = heldCommit();
	h.queue.defer({ message: 'Removed', commit: held.commit, restore: restore.fn, onCommitError: onCommitError.fn });
	const flushing = h.queue.flush();
	h.setOwner(undefined);
	const boom = new Error('JWT expired');
	held.fail(boom);
	await flushing;
	assert.equal(restore.count, 1);
	assert.deepEqual(onCommitError.calls, [[boom]]);
});

test('a delete queued before the account was known restores for the account that turns up', async () => {
	const h = harness();
	h.setOwner(undefined);
	const restore = spy();
	const onCommitError = spy();
	const held = heldCommit();
	h.queue.defer({ message: 'Removed', commit: held.commit, restore: restore.fn, onCommitError: onCommitError.fn });
	const flushing = h.queue.flush();
	h.setOwner('a');
	held.fail(new Error('boom'));
	await flushing;
	assert.equal(restore.count, 1);
	assert.equal(onCommitError.count, 1);
});

test('only an ended session or a different known account counts as the owner changing', () => {
	assert.equal(undoOwnerChanged('a', 'a'), false);
	assert.equal(undoOwnerChanged('a', undefined), false, 'not known yet is not a sign-out');
	assert.equal(undoOwnerChanged(undefined, 'a'), false);
	assert.equal(undoOwnerChanged(undefined, undefined), false);
	assert.equal(undoOwnerChanged('a', null), true, 'the session ended');
	assert.equal(undoOwnerChanged(undefined, null), true);
	assert.equal(undoOwnerChanged('a', 'b'), true, 'another account signed in');
});

test('the owner is the account signed in when the delete was queued, not when it commits', async () => {
	const h = harness();
	h.setOwner('b');
	const restore = spy();
	const onCommitError = spy();
	const held = heldCommit();
	h.queue.defer({ message: 'Removed', commit: held.commit, restore: restore.fn, onCommitError: onCommitError.fn });
	const flushing = h.queue.flush();
	held.fail(new Error('boom'));
	await flushing;
	assert.equal(restore.count, 1);
	assert.equal(onCommitError.count, 1);
});

// ---------------------------------------------------------------------------
// One slot
// ---------------------------------------------------------------------------

test('a second destruction commits the first immediately and takes the slot', async () => {
	const h = harness();
	const firstCommit = spy();
	const secondCommit = spy();
	const firstRestore = spy();
	h.queue.defer({ message: 'One', commit: async () => firstCommit.fn(), restore: firstRestore.fn });
	h.queue.defer({ message: 'Two', commit: async () => secondCommit.fn(), restore: () => {} });
	await Promise.resolve();
	assert.equal(firstCommit.count, 1, 'the displaced entry commits');
	assert.equal(firstRestore.count, 0, 'and is not restored — the user did not undo it');
	assert.equal(secondCommit.count, 0);
	assert.equal((h.published.at(-1) as PendingUndo).message, 'Two');
	assert.equal(h.armedTimers(), 1, 'the displaced timer was disarmed');
});

test('undo after the window closed is a no-op — a stale click cannot double-fire', async () => {
	const h = harness();
	const commit = spy();
	const restore = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: restore.fn });
	await h.advance(8000);
	h.queue.undo();
	assert.equal(commit.count, 1);
	assert.equal(restore.count, 0, 'the row is genuinely gone — undo must not claim otherwise');
});

test('flush is idempotent and a no-op with nothing pending', async () => {
	const h = harness();
	const commit = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: () => {} });
	await h.queue.flush();
	await h.queue.flush();
	assert.equal(commit.count, 1);
});

// Reason: flush returned at once when the slot was already empty, so a
// sign-out that awaited it went ahead while a commit the window timer (or a
// second delete) had started was still on the wire, and that commit's failure
// was only logged to a signed-out reader instead of restored and reported.
test('flush waits for a commit the window timer already started, and its failure reports first', async () => {
	const h = harness();
	const order: string[] = [];
	let fail!: (e: Error) => void;
	h.queue.defer({
		message: 'Removed',
		commit: () => new Promise<void>((_, reject) => (fail = reject)),
		restore: () => order.push('restore'),
		onCommitError: () => order.push('report'),
	});
	await h.advance(8000);
	assert.equal(h.queue.hasPending(), false, 'the timer took the entry');
	const flushed = h.queue.flush().then(() => order.push('flushed'));
	await Promise.resolve();
	await Promise.resolve();
	assert.deepEqual(order, [], 'flush is still waiting on the in-flight commit');
	fail(new Error('500'));
	await flushed;
	assert.deepEqual(order, ['restore', 'report', 'flushed']);
});

test('flush waits for the commit a second destruction displaced', async () => {
	const h = harness();
	const order: string[] = [];
	let land!: () => void;
	h.queue.defer({
		message: 'One',
		commit: () => new Promise<void>((r) => (land = r)),
		restore: () => {},
	});
	h.queue.defer({ message: 'Two', commit: async () => void order.push('two'), restore: () => {} });
	const flushed = h.queue.flush().then(() => order.push('flushed'));
	await Promise.resolve();
	await Promise.resolve();
	assert.deepEqual(order, ['two'], 'the slot committed, the displaced one has not landed');
	land();
	await flushed;
	assert.deepEqual(order, ['two', 'flushed']);
});

test('a settled commit is no longer waited on', async () => {
	const h = harness();
	h.queue.defer({ message: 'Removed', commit: async () => {}, restore: () => {} });
	await h.advance(8000);
	let done = false;
	const flushed = h.queue.flush().then(() => (done = true));
	await Promise.resolve();
	await Promise.resolve();
	await flushed;
	assert.equal(done, true);
});

// ---------------------------------------------------------------------------
// WCAG 2.2.1 — pause while the bar has hover/focus, and turn the limit off
// ---------------------------------------------------------------------------

test('pause disarms the timer; resume re-arms with only the remaining time', async () => {
	const h = harness();
	const commit = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: () => {} });
	await h.advance(3000);
	h.queue.pause();
	assert.equal(h.armedTimers(), 0);
	assert.equal((h.published.at(-1) as PendingUndo).paused, true);

	// A long hover must not consume any of the window.
	h.tick(60_000);
	assert.equal(commit.count, 0);

	h.queue.resume();
	assert.equal((h.published.at(-1) as PendingUndo).paused, false);
	await h.advance(4999);
	assert.equal(commit.count, 0, '5 s of the 8 s window remained');
	await h.advance(1);
	assert.equal(commit.count, 1);
});

test('pause/resume keep the published id and windowMs stable so the bar animation does not restart', async () => {
	const h = harness();
	h.queue.defer({ message: 'Removed', commit: async () => {}, restore: () => {} });
	await h.advance(2000);
	h.queue.pause();
	h.queue.resume();
	const ids = h.published.filter((p) => p !== null).map((p) => (p as PendingUndo).id);
	assert.deepEqual(ids, [1, 1, 1]);
	for (const p of h.published) {
		if (p !== null) assert.equal(p.windowMs, 8000);
	}
});

test('a zero window arms no timer at all — the limit is off until dismiss or undo', async () => {
	const h = harness();
	h.setWindowMs(0);
	const commit = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: () => {} });
	assert.equal(h.armedTimers(), 0);
	assert.equal((h.published.at(-1) as PendingUndo).windowMs, 0);
	await h.advance(10 * 60_000);
	assert.equal(commit.count, 0, 'ten minutes later it is still undoable');
	await h.queue.flush();
	assert.equal(commit.count, 1);
});

test('pause and resume are inert when there is no time limit to pause', () => {
	const h = harness();
	h.setWindowMs(0);
	h.queue.defer({ message: 'Removed', commit: async () => {}, restore: () => {} });
	h.queue.pause();
	h.queue.resume();
	assert.equal((h.published.at(-1) as PendingUndo).paused, false);
});

test('a negative window is clamped to no-limit rather than firing instantly', () => {
	const h = harness();
	h.setWindowMs(-5000);
	const commit = spy();
	h.queue.defer({ message: 'Removed', commit: async () => commit.fn(), restore: () => {} });
	assert.equal(h.armedTimers(), 0);
	assert.equal(commit.count, 0);
});

// ---------------------------------------------------------------------------
// undoWindowSFromPref — the stored preference
// ---------------------------------------------------------------------------

test('undoWindowSFromPref: every offered choice round-trips', () => {
	for (const choice of UNDO_WINDOW_CHOICES_S) {
		assert.equal(undoWindowSFromPref(choice), choice);
	}
});

test('undoWindowSFromPref: absent or corrupt values fall back to the default, never to no-limit', () => {
	for (const raw of [undefined, null, '8', '', {}, [], NaN, Infinity, 7, -1, 3600]) {
		assert.equal(undoWindowSFromPref(raw), DEFAULT_UNDO_WINDOW_S);
	}
});
