/**
 * The runner's own mute / archive writes, held against the inbox list reads
 * that race them.
 *
 * The inbox polls `dm_threads()` while a write is in flight. A read that
 * started before the write landed answers with the state from before it, and
 * assigning that as-is flipped the toggle back; restoring a snapshot of the
 * whole list on a refused write threw away everything a poll had brought in
 * meanwhile. Each write is therefore kept here, per conversation and flag,
 * until a read started after it landed carries it, and a refused write puts
 * back the one field it changed. A deleted conversation brought back by Undo
 * (or a refused delete) is likewise put back as one row, not as the list from
 * before the delete.
 *
 * Web only: the mobile store keeps its own (apps/mobile_android).
 */

export type ConversationFlag = 'muted' | 'archived';

export interface ConversationFlags {
	conversationId: string;
	muted: boolean;
	archived: boolean;
}

export interface ConversationWrite {
	conversationId: string;
	flag: ConversationFlag;
	value: boolean;
	/// When the server accepted it, in ms; `Infinity` while it is in flight.
	at: number;
}

export function conversationWriteKey(conversationId: string, flag: ConversationFlag): string {
	return `${conversationId}:${flag}`;
}

/// A read that started at or before a write landed may not carry it, so the
/// write wins for that read.
function overrides(write: ConversationWrite, readStartedAt: number): boolean {
	return write.at >= readStartedAt;
}

/// The rows a list read returned, with every write that read may predate laid
/// over them.
export function overlayConversationWrites<T extends ConversationFlags>(
	rows: readonly T[],
	writes: Iterable<ConversationWrite>,
	readStartedAt: number,
): T[] {
	const byConversation = new Map<string, Partial<Record<ConversationFlag, boolean>>>();
	for (const w of writes) {
		if (!overrides(w, readStartedAt)) continue;
		byConversation.set(w.conversationId, { ...byConversation.get(w.conversationId), [w.flag]: w.value });
	}
	if (byConversation.size === 0) return [...rows];
	return rows.map((row) => {
		const change = byConversation.get(row.conversationId);
		return change ? { ...row, ...change } : row;
	});
}

/// The writes a read started at `readStartedAt` already carries; they can be
/// forgotten once that read is applied.
export function settledConversationWrites(
	writes: Iterable<ConversationWrite>,
	readStartedAt: number,
): ConversationWrite[] {
	return [...writes].filter((w) => !overrides(w, readStartedAt));
}

/// A refused write is forgotten only while it is still the latest one for its
/// conversation and flag. Returns whether the caller should revert the field:
/// when a later write superseded it, that write owns the field, and putting
/// back the value from before the refused one would overwrite it.
export function dropRefusedWrite(
	writes: Map<string, ConversationWrite>,
	refused: ConversationWrite,
): boolean {
	const key = conversationWriteKey(refused.conversationId, refused.flag);
	if (writes.get(key) !== refused) return false;
	writes.delete(key);
	return true;
}

/// Puts back the one field a refused write changed, leaving every other row
/// and field as the latest read left them.
export function revertConversationFlag<T extends ConversationFlags>(
	rows: readonly T[],
	conversationId: string,
	flag: ConversationFlag,
	value: boolean,
): T[] {
	return rows.map((row) => (row.conversationId === conversationId ? { ...row, [flag]: value } : row));
}

/// Puts a conversation whose delete was undone or refused back into the list,
/// at its place by latest message, keeping every row the reads since the
/// delete brought in. Null when the row was never in the list (the delete
/// came from a conversation opened before the list loaded): the caller reads
/// the list instead.
export function restoreHiddenConversation<T extends { conversationId: string; lastAt: string }>(
	rows: readonly T[],
	hidden: T | undefined,
): T[] | null {
	if (!hidden) return null;
	if (rows.some((r) => r.conversationId === hidden.conversationId)) return [...rows];
	const at = Date.parse(hidden.lastAt);
	const i = rows.findIndex((r) => Date.parse(r.lastAt) < at);
	const out = [...rows];
	out.splice(i === -1 ? out.length : i, 0, hidden);
	return out;
}
