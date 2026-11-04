/**
 * The nav badge's count with the conversations whose delete is still inside
 * its undo window left out. The server has not been told about those yet, so
 * every `dm_threads()` read still counts them; the badge drops them at once
 * and re-reads only when the window closes or is undone.
 *
 * Web only: mobile filters the same way in `you_screen.dart` over
 * `DmPendingHides`.
 */
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
