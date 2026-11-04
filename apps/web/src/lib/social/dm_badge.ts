/**
 * The nav badge's count with the conversations whose delete is still inside
 * its undo window left out. The server has not been told about those yet, so
 * every `dm_threads()` read still counts them; the badge drops them at once
 * and re-reads only when the window closes or is undone.
 *
 * Web only: mobile filters the same way in `you_screen.dart` over
 * `DmPendingHides`.
 */
import { CoalescingRefetcher } from '#lib/runs/live_refetch.ts';
import { unreadDmBadgeCount, type DmThreadState } from './messages_inbox.ts';

export interface DmBadgeState extends DmThreadState {
	conversationId: string;
}

export function unreadDmBadgeCountExcept(
	states: readonly DmBadgeState[],
	pendingHidden: ReadonlySet<string>,
): number {
	return unreadDmBadgeCount(states.filter((s) => !pendingHidden.has(s.conversationId)));
}

/// The badge's reads, each tagged with the account it started under. A read
/// that lands after the badge was bound to another account (a sign-out, or a
/// sign-in in another tab) is dropped, so it can never show one account's
/// count to the next or to a signed-out reader. Only the newest read is
/// applied (`CoalescingRefetcher`), so a read from before a delete cannot land
/// after it either. Rune-free so it runs under `tsx --test`; the reactive
/// store is `stores/dm_unread.svelte.ts`.
export class DmBadgeReader {
	#userId: string | null = null;
	readonly #refetcher: CoalescingRefetcher<{ userId: string; states: DmBadgeState[] }>;

	constructor(opts: {
		fetch: () => Promise<DmBadgeState[]>;
		apply: (states: DmBadgeState[]) => void;
		onError: (err: unknown) => void;
	}) {
		this.#refetcher = new CoalescingRefetcher({
			fetch: async () => {
				const userId = this.#userId as string;
				return { userId, states: await opts.fetch() };
			},
			apply: ({ userId, states }) => {
				if (userId === this.#userId) opts.apply(states);
			},
			onError: opts.onError,
		});
	}

	/// Returns whether the account changed, so the caller can drop what it holds.
	bind(userId: string | null): boolean {
		if (userId === this.#userId) return false;
		this.#userId = userId;
		return true;
	}

	async refresh(): Promise<void> {
		if (this.#userId === null) return;
		await this.#refetcher.runNow();
	}
}
