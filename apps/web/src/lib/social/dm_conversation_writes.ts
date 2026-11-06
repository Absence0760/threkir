/**
 * The runner's own mute / archive / mark-unread writes, held against the inbox list reads
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
 * before the delete. A delete is held the same way: a read that started
 * before the server hid the conversation still lists it, so the row is left
 * out of every such read until one started after the delete landed is
 * applied.
 *
 * Web only: the mobile store keeps its own (apps/mobile_android).
 */

export type ConversationFlag = 'muted' | 'archived' | 'markedUnread';

export interface ConversationFlags {
	conversationId: string;
	muted: boolean;
	archived: boolean;
	markedUnread?: boolean;
}

export interface ConversationWrite {
	conversationId: string;
	flag: ConversationFlag;
	value: boolean;
	/// When the server accepted it, in ms; `Infinity` while it is in flight.
	at: number;
	/// What the server held before this write, as far as the client knows;
	/// a refusal puts this back. Undefined when the list never held the row.
	/// Updated in place when an earlier write to the same flag lands while
	/// this one is in flight.
	prior?: boolean;
}

/// What the server holds for a flag before a new write to it: the value of
/// the last write that landed, or, while one is still in flight, what that
/// one would put back. The list itself shows the in-flight value, so reading
/// the prior off it made a second refused write restore the first one's.
export function confirmedFlagValue(
	previous: ConversationWrite | undefined,
	listed: boolean | undefined,
): boolean | undefined {
	if (!previous) return listed;
	return previous.at === Infinity ? previous.prior : previous.value;
}

/// Records that `landed` was accepted at `at`. A later write to the same flag
/// still in flight now reverts to this value if it is refused.
export function settleLandedWrite(
	writes: Map<string, ConversationWrite>,
	landed: ConversationWrite,
	at: number,
): void {
	const key = conversationWriteKey(landed.conversationId, landed.flag);
	const latest = writes.get(key);
	if (latest === landed) writes.set(key, { ...landed, at });
	else if (latest && latest.at === Infinity) latest.prior = landed.value;
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

/// The rows a list read returned, without the conversations deleted since that
/// read started. `hiddenAt` maps a conversation to when its delete landed, in
/// ms, or `Infinity` while its undo window is open or the delete is in flight.
export function withoutHiddenConversations<T extends { conversationId: string }>(
	rows: readonly T[],
	hiddenAt: ReadonlyMap<string, number>,
	readStartedAt: number,
): T[] {
	if (hiddenAt.size === 0) return [...rows];
	return rows.filter((r) => (hiddenAt.get(r.conversationId) ?? -Infinity) < readStartedAt);
}

/// The deletes a read started at `readStartedAt` already carries; their
/// markers can be forgotten once that read is applied.
export function settledHides(hiddenAt: ReadonlyMap<string, number>, readStartedAt: number): string[] {
	return [...hiddenAt].filter(([, at]) => at < readStartedAt).map(([id]) => id);
}
