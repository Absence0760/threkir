/**
 * The Messages inbox: the runner's direct-message conversations plus the AI
 * Coach as one more row (issue #1215, decisions § 2227).
 *
 * The two are merged here, in the list, and nowhere else. `direct_messages`
 * and `coach_messages` keep their own tables, RLS, retention and rendering
 * (decisions § 110): nothing in this module reads a message body beyond the
 * coach row's plain-text preview, and no AI text is ever placed in a human
 * conversation.
 *
 * Mobile twin: `apps/mobile_android/lib/messages_inbox.dart`.
 */

/// Where the AI Coach sits in the inbox. `pinned` keeps it above every
/// conversation, `listed` files it among them by its latest message, and
/// `hidden` leaves it out. The runner picks this freely, on any tier.
export type CoachInboxPlacement = 'pinned' | 'listed' | 'hidden';

/// The universal settings key the placement is stored under
/// (docs/backend/settings.md).
export const MESSAGES_COACH_ROW_KEY = 'messages_coach_row';

export const COACH_INBOX_PLACEMENTS: readonly CoachInboxPlacement[] = ['pinned', 'listed', 'hidden'];

/// The stored placement. Anything but the two non-default spellings reads as
/// `pinned`: an absent key is a runner who never chose, and a corrupt one is
/// not a decision to hide the Coach.
export function parseCoachInboxPlacement(raw: unknown): CoachInboxPlacement {
	return raw === 'listed' || raw === 'hidden' ? raw : 'pinned';
}

/// One row of the inbox.
export type InboxEntry<T> = { kind: 'coach' } | { kind: 'dm'; thread: T };

export interface CoachInboxRow {
	placement: CoachInboxPlacement;
	/// When the newest Coach message was written; null when there is none, or
	/// when it was not read because the runner has not consented to the
	/// Coach. A `listed` row with no time goes after every conversation.
	lastAt: string | null;
}

function instantMs(iso: string): number {
	const ms = Date.parse(iso);
	return Number.isNaN(ms) ? Number.NEGATIVE_INFINITY : ms;
}

/**
 * The inbox's rows in display order. `threads` keep the order they came in
 * (`dm_threads()` returns newest first); the Coach row is placed among them.
 * `coach` is null when the Coach is off for this deploy or this runner, and
 * then the inbox is the conversations alone.
 *
 * A listed Coach row goes before the first conversation whose latest message
 * is strictly older than its own, so on a tie the conversation stays first.
 */
export function inboxEntries<T extends { lastAt: string }>(
	threads: readonly T[],
	coach: CoachInboxRow | null
): InboxEntry<T>[] {
	const dms: InboxEntry<T>[] = threads.map((thread) => ({ kind: 'dm', thread }));
	if (coach === null || coach.placement === 'hidden') return dms;
	const row: InboxEntry<T> = { kind: 'coach' };
	if (coach.placement === 'pinned') return [row, ...dms];
	if (coach.lastAt === null) return [...dms, row];
	const at = instantMs(coach.lastAt);
	const index = threads.findIndex((t) => instantMs(t.lastAt) < at);
	if (index === -1) return [...dms, row];
	return [...dms.slice(0, index), row, ...dms.slice(index)];
}

/// How long the Coach row's preview may run, in code points, before it is cut
/// with an ellipsis.
export const COACH_PREVIEW_MAX = 140;

/**
 * A Coach message as one line of plain text for the inbox row. The Coach
 * writes markdown; the row shows text only, so the markup is dropped rather
 * than rendered, and the result is always placed as a text node.
 */
export function coachInboxPreview(content: string): string {
	const text = content
		.replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
		.replace(/```[^\n]*/g, ' ')
		.replace(/`/g, '')
		.replace(/^[ \t]*(?:#{1,6}|>|[-*+]|\d+[.)])[ \t]+/gm, '')
		.replace(/\*\*|__|~~|\*/g, '')
		.replace(/\s+/g, ' ')
		.trim();
	const points = Array.from(text);
	if (points.length <= COACH_PREVIEW_MAX) return text;
	return points.slice(0, COACH_PREVIEW_MAX - 1).join('').trimEnd() + '…';
}
