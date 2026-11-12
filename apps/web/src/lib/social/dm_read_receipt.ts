/**
 * Read receipts in one direct-message conversation (issue #1216, migration
 * 20271113000001). The server decides whether a read is shared: `seen_at` is
 * set only while both participants have receipts on, and the recipient's own
 * `read_at` is never granted to a client. These helpers only place what the
 * server returned. Mobile twin: `dm_read_receipt.dart`.
 */

export interface DmReceiptMessage {
	id: string;
	sender_id: string;
	seen_at: string | null;
}

/**
 * The viewer's newest message the partner has seen, the one "Seen" sits
 * under, or null. `messages` is oldest first, the order the thread renders in.
 */
export function seenReceipt<T extends DmReceiptMessage>(
	messages: readonly T[],
	viewerId: string | null | undefined,
): T | null {
	if (!viewerId) return null;
	for (let i = messages.length - 1; i >= 0; i--) {
		const m = messages[i];
		if (m.sender_id === viewerId && m.seen_at !== null) return m;
	}
	return null;
}

/**
 * The partner message to mark the conversation read through: the newest one
 * on screen, unless it is the one already marked. Null when there is nothing
 * new from the partner. A client cannot see which messages it has read
 * (`read_at` is withheld), so it remembers how far it marked instead.
 */
export function dmMarkReadThrough<T extends Pick<DmReceiptMessage, 'id' | 'sender_id'>>(
	messages: readonly T[],
	partnerId: string,
	markedThroughId: string | null,
): string | null {
	for (let i = messages.length - 1; i >= 0; i--) {
		const m = messages[i];
		if (m.sender_id === partnerId) return m.id === markedThroughId ? null : m.id;
	}
	return null;
}
