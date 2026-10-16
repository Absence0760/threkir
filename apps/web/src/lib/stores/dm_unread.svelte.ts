/**
 * Unread direct-message count for the sidebar's Messages entry, the web
 * counterpart of the badge on mobile's inbox icon (decisions § 2007).
 *
 * Refresh triggers: auth-ready, window focus, a 60 s poll while the tab is
 * visible, and an explicit `refresh()` from /messages after it marks a thread
 * read. Polled rather than Realtime because `direct_messages` is not in the
 * Realtime publication, and the inbox itself polls.
 */
import { fetchUnreadDmCount } from '#lib/core/data.ts';
import { CoalescingRefetcher } from '#lib/runs/live_refetch.ts';

export const DM_UNREAD_POLL_MS = 60_000;

class DmUnreadStore {
	count = $state(0);

	#refetcher = new CoalescingRefetcher<number>({
		fetch: () => fetchUnreadDmCount(),
		apply: (count) => {
			this.count = count;
		},
		onError: (e) => console.warn('unread DM refresh failed', e),
	});

	async refresh() {
		await this.#refetcher.runNow();
	}

	clear() {
		this.count = 0;
	}
}

export const dmUnreadStore = new DmUnreadStore();
