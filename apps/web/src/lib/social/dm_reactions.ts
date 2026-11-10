/**
 * Reactions on a direct message (issue #1216, migration 20271213121602).
 *
 * The server stores a key from a fixed set, CHECKed on
 * `direct_message_reactions.reaction`; `set_direct_message_reaction` decides
 * who may react. A glyph is built from its Unicode codepoints here, so no
 * source file carries an emoji literal and the stored value is never a glyph.
 * Mobile twin: `dm_reactions.dart`.
 */

export type DmReaction = 'thumbs_up' | 'heart' | 'laugh' | 'surprised' | 'sad' | 'fire';

/** Every key the CHECK admits, in the order the picker and the summary use. */
export const DM_REACTIONS = [
	'thumbs_up',
	'heart',
	'laugh',
	'surprised',
	'sad',
	'fire',
] as const satisfies readonly DmReaction[];

/** The codepoints each key draws as. */
export const DM_REACTION_CODEPOINTS: Record<DmReaction, readonly number[]> = {
	thumbs_up: [0x1f44d],
	heart: [0x2764, 0xfe0f],
	laugh: [0x1f602],
	surprised: [0x1f62e],
	sad: [0x1f622],
	fire: [0x1f525],
};

export function parseDmReaction(raw: unknown): DmReaction | null {
	return typeof raw === 'string' && (DM_REACTIONS as readonly string[]).includes(raw)
		? (raw as DmReaction)
		: null;
}

export function dmReactionGlyph(reaction: DmReaction): string {
	return String.fromCodePoint(...DM_REACTION_CODEPOINTS[reaction]);
}

export interface DmReactionRow {
	message_id: string;
	user_id: string;
	reaction: string;
}

export interface DmReactionSummary {
	reaction: DmReaction;
	count: number;
	mine: boolean;
}

/**
 * The chips under one message: one per key that anyone used, in
 * `DM_REACTIONS` order, with whether the viewer's own reaction is that key.
 * Rows for other messages and unknown keys are ignored.
 */
export function summarizeDmReactions(
	rows: readonly DmReactionRow[],
	messageId: string,
	viewerId: string | null | undefined,
): DmReactionSummary[] {
	const counts = new Map<DmReaction, { count: number; mine: boolean }>();
	for (const r of rows) {
		if (r.message_id !== messageId) continue;
		const key = parseDmReaction(r.reaction);
		if (!key) continue;
		const c = counts.get(key) ?? { count: 0, mine: false };
		c.count += 1;
		if (viewerId && r.user_id === viewerId) c.mine = true;
		counts.set(key, c);
	}
	return DM_REACTIONS.flatMap((reaction) => {
		const c = counts.get(reaction);
		return c ? [{ reaction, count: c.count, mine: c.mine }] : [];
	});
}

/** The viewer's own reaction on a message, if any. */
export function myDmReaction(
	rows: readonly DmReactionRow[],
	messageId: string,
	viewerId: string | null | undefined,
): DmReaction | null {
	if (!viewerId) return null;
	const row = rows.find((r) => r.message_id === messageId && r.user_id === viewerId);
	return row ? parseDmReaction(row.reaction) : null;
}

/**
 * The rows after the viewer sets `next` (null clears) on a message, applied
 * locally before the server answers so the chip moves at once.
 */
export function withMyDmReaction<T extends DmReactionRow>(
	rows: readonly T[],
	messageId: string,
	viewerId: string,
	next: DmReaction | null,
	make: (reaction: DmReaction) => T,
): T[] {
	const rest = rows.filter((r) => !(r.message_id === messageId && r.user_id === viewerId));
	return next ? [...rest, make(next)] : rest;
}
