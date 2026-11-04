/**
 * Unread direct-message count for the sidebar's Messages entry, the web
 * counterpart of the badge on mobile's inbox icon (decisions § 2007).
 *
 * Refresh triggers: auth-ready, window focus, a 60 s poll while the tab is
 * visible, and an explicit `refresh()` from /messages after it marks a thread
 * read. Polled rather than Realtime because `direct_messages` is not in the
 * Realtime publication, and the inbox itself polls.
 *
 * A conversation whose delete is inside its undo window (`dmPendingHides`)
 * leaves the count at once, from the states already held; the inbox store
 * re-reads only when the window closes or is undone, since only the server
 * knows the outcome.
 *
 * Each read carries the account it started under and is dropped if the badge
 * was bound to another account (or none) by the time it lands — a read the
 * sign-out's own undo commit starts would otherwise repaint the previous
 * account's count after `clear()`.
 */
import { fetchDmBadgeStates } from '#lib/core/data.ts';
import { DmBadgeReader, unreadDmBadgeCountExcept, type DmBadgeState } from '#lib/social/dm_badge.ts';
import { dmPendingHides } from '#lib/stores/dm_pending_hides.svelte.ts';

export const DM_UNREAD_POLL_MS = 60_000;

class DmUnreadStore {
	#states = $state<DmBadgeState[]>([]);
	count = $derived(unreadDmBadgeCountExcept(this.#states, dmPendingHides));

	#reader = new DmBadgeReader({
		fetch: () => fetchDmBadgeStates(),
		apply: (states) => {
			this.#states = states;
		},
		onError: (e) => console.warn('unread DM refresh failed', e),
	});

	bind(userId: string) {
		if (this.#reader.bind(userId)) this.#states = [];
	}

	async refresh() {
		await this.#reader.refresh();
	}

	/// A conversation the server has just hidden for the runner.
	forget(conversationId: string) {
		this.#states = this.#states.filter((s) => s.conversationId !== conversationId);
	}

	clear() {
		this.#reader.bind(null);
		this.#states = [];
	}
}

export const dmUnreadStore = new DmUnreadStore();
