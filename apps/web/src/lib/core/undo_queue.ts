/**
 * Deferred-commit undo — the rune-free core of the web app's undo contract.
 *
 * The app had no undo anywhere: every destructive action was
 * confirm-then-gone. Three contracts were on the table and only one of
 * them can be honest for the actions we adopt it on:
 *
 *   1. A compensating inverse (re-insert what was deleted) mints a NEW
 *      server id, and anything the original row owned — cascaded
 *      replies, a Storage object's bytes — is already unrecoverable. An
 *      "Undo" that hands back a different row is a lie.
 *   2. A soft delete + restore is the honest answer for a *trash*
 *      feature, but it costs a `deleted_at` column on every adopting
 *      table, an RLS/read-path filter everywhere, and a retention story.
 *   3. Deferring the mutation until the undo window closes means
 *      **nothing is destroyed while undo is on offer**, so undo cannot
 *      fail. That is this module.
 *
 * The row leaves the caller's local list immediately (the action feels
 * done) while `commit` is held. Undo cancels the pending commit and
 * calls `restore`; the server was never touched. A commit that later
 * fails also calls `restore`, so a list never claims a row is gone
 * while the server still holds it — unless the account that queued it
 * is provably no longer the one signed in: the session has ended, or a
 * different account is signed in (another tab changed it while the
 * commit was in flight). That failure is logged and nothing else: no
 * toast to a signed-out reader, and no restore into what is now another
 * account's list. An owner that is merely not known yet (the profile is
 * still hydrating for a live session) is not a change, so the same
 * account's failure still restores and reports.
 *
 * One slot, deliberately: a second destruction commits the first
 * immediately rather than stacking bars whose ordering the user would
 * have to reason about.
 *
 * Kept rune-free so it is `tsx --test`-runnable (see undo_queue.test.ts);
 * the reactive wrapper lives in stores/undo.svelte.ts.
 */

/// The undo window in seconds, keyed by the `undo_window_s` pref.
/// `0` turns the time limit off entirely — the WCAG 2.2.1 "Turn off"
/// route, so a screen-reader or motor-impaired user is never racing a
/// countdown to reach the only undo affordance.
export const UNDO_WINDOW_CHOICES_S = [8, 30, 0] as const;
export const DEFAULT_UNDO_WINDOW_S = 8;

/// Normalises a stored `undo_window_s` bag value. An absent, corrupt, or
/// unrecognised value falls back to the default rather than to `0` — a
/// garbage bag must not silently pin every destructive action open
/// forever, which would leave the user's list disagreeing with the
/// server until they navigate.
export function undoWindowSFromPref(raw: unknown): number {
	if (typeof raw !== 'number' || !Number.isFinite(raw)) return DEFAULT_UNDO_WINDOW_S;
	return (UNDO_WINDOW_CHOICES_S as readonly number[]).includes(raw) ? raw : DEFAULT_UNDO_WINDOW_S;
}

export interface DeferredDestruction {
	/// Already-localized sentence for the undo bar ("Porridge removed").
	message: string;
	/// The server mutation. Runs when the window closes — never at the
	/// moment the user clicks delete.
	commit: () => Promise<void>;
	/// Puts the caller's local state back exactly as it was. Run on undo
	/// and on a commit failure.
	restore: () => void;
	/// Surfaces a commit failure at the call site (a toast, a banner).
	onCommitError?: (error: unknown) => void;
}

export interface PendingUndo {
	id: number;
	message: string;
	/// How long the bar has to run, in ms. `0` means there is no time
	/// limit at all — the user's chosen "until I dismiss it" window.
	windowMs: number;
	paused: boolean;
}

type TimerHandle = unknown;

/// An account id, `null` for a session that has ended, or `undefined` for a
/// live session whose account is not known yet.
export type UndoOwner = string | null | undefined;

/// Whether a commit failure belongs to someone other than the account that
/// queued it. Only a confirmed end, or a different known account, counts: a
/// gap in what the app knows about the same session is not a sign-out.
export function undoOwnerChanged(queuedBy: UndoOwner, now: UndoOwner): boolean {
	if (now === undefined) return false;
	if (now === null) return true;
	return typeof queuedBy === 'string' && now !== queuedBy;
}

export interface UndoQueueDeps {
	/// The undo window in ms, read at defer time. `0` or less disables
	/// the timer entirely (WCAG 2.2.1 "turn off").
	windowMs: () => number;
	setTimer: (cb: () => void, ms: number) => TimerHandle;
	clearTimer: (handle: TimerHandle) => void;
	now: () => number;
	onChange: (pending: PendingUndo | null) => void;
	/// The signed-in account, read when a destruction is queued and again
	/// when its commit fails: its id, `null` once the session has ended, or
	/// `undefined` while a live session's account is not known yet. Absent,
	/// every destruction has one owner.
	owner?: () => UndoOwner;
}

export interface UndoQueue {
	defer: (destruction: DeferredDestruction) => void;
	undo: () => void;
	/// Commit the pending destruction now — the dismiss button, a
	/// navigation, a second destruction arriving, or a sign-out. Resolves
	/// once every commit this queue has started has settled, including one
	/// the window timer or a later `defer` set going before this call: a
	/// sign-out that awaits it ends the session only after a failure has
	/// restored and reported to the account that made the delete.
	flush: () => Promise<void>;
	pause: () => void;
	resume: () => void;
	hasPending: () => boolean;
}

export function createUndoQueue(deps: UndoQueueDeps): UndoQueue {
	const owner = deps.owner ?? ((): UndoOwner => undefined);
	let nextId = 1;
	let current: {
		id: number;
		owner: UndoOwner;
		destruction: DeferredDestruction;
		windowMs: number;
		remainingMs: number;
		startedAt: number;
		paused: boolean;
		timer: TimerHandle | null;
		settled: boolean;
	} | null = null;

	function publish(): void {
		deps.onChange(
			current === null
				? null
				: {
						id: current.id,
						message: current.destruction.message,
						windowMs: current.windowMs,
						paused: current.paused,
					},
		);
	}

	function disarm(): void {
		if (current?.timer != null) {
			deps.clearTimer(current.timer);
			current.timer = null;
		}
	}

	function arm(): void {
		if (current === null || current.windowMs <= 0) return;
		current.startedAt = deps.now();
		current.timer = deps.setTimer(() => void flush(), current.remainingMs);
	}

	/// Detaches the pending entry so a concurrent flush/undo/defer can't
	/// act on it twice. Returns null when there was nothing pending.
	function take(): { destruction: DeferredDestruction; owner: UndoOwner } | null {
		const c = current;
		if (c === null || c.settled) return null;
		c.settled = true;
		disarm();
		current = null;
		publish();
		return { destruction: c.destruction, owner: c.owner };
	}

	/// Commits that have left the slot and not yet settled. `take` detaches
	/// an entry before its commit runs, so without this a flush that found
	/// the slot empty could not see a commit the timer or `defer` had
	/// already started.
	const inFlight = new Set<Promise<void>>();

	function settle(taken: { destruction: DeferredDestruction; owner: UndoOwner }): Promise<void> {
		const { destruction } = taken;
		const settling = (async () => {
			try {
				await destruction.commit();
			} catch (error) {
				if (undoOwnerChanged(taken.owner, owner())) {
					console.error('undo: a held delete failed after the account that made it signed out', error);
					return;
				}
				destruction.restore();
				destruction.onCommitError?.(error);
			}
		})();
		inFlight.add(settling);
		const forget = () => {
			inFlight.delete(settling);
		};
		settling.then(forget, forget);
		return settling;
	}

	async function flush(): Promise<void> {
		const taken = take();
		const own = taken === null ? null : settle(taken);
		await Promise.allSettled([...inFlight].filter((p) => p !== own));
		if (own !== null) await own;
	}

	function defer(destruction: DeferredDestruction): void {
		void flush();
		const windowMs = Math.max(0, deps.windowMs());
		current = {
			id: nextId++,
			owner: owner(),
			destruction,
			windowMs,
			remainingMs: windowMs,
			startedAt: deps.now(),
			paused: false,
			timer: null,
			settled: false,
		};
		arm();
		publish();
	}

	function undo(): void {
		const taken = take();
		if (taken === null) return;
		taken.destruction.restore();
	}

	function pause(): void {
		const c = current;
		if (c === null || c.paused || c.windowMs <= 0) return;
		const elapsed = deps.now() - c.startedAt;
		c.remainingMs = Math.max(0, c.remainingMs - elapsed);
		disarm();
		c.paused = true;
		publish();
	}

	function resume(): void {
		const c = current;
		if (c === null || !c.paused || c.windowMs <= 0) return;
		c.paused = false;
		arm();
		publish();
	}

	return { defer, undo, flush, pause, resume, hasPending: () => current !== null };
}
