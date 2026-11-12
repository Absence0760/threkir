// @mentions in run comments (decisions § 1971). TS↔Dart parity pair with
// apps/mobile_android/lib/mentions.dart, and the client half of
// private.extract_mention_handles (migration 20270826000001): the same rule
// decides what the server notifies and what the clients draw as a mention.
//
// A mention is `@` followed by a § 269 handle — 3 to 30 of [A-Za-z0-9_] — that
// is not glued to a word or a second `@` on its left, so `me@example.com`
// mentions nobody, and is not followed by another handle character, so a
// 31-character run is not truncated into a 30-character handle.

export const MAX_MENTIONS_PER_COMMENT = 10;

const MENTION = /(?<![A-Za-z0-9_@])@([A-Za-z0-9_]{3,30})(?![A-Za-z0-9_])/g;

/** The lowercased, de-duplicated handles a body mentions, first-seen order, at most ten. */
export function parseMentionHandles(body: string): string[] {
	const out: string[] = [];
	for (const m of body.matchAll(MENTION)) {
		const handle = m[1].toLowerCase();
		if (out.includes(handle)) continue;
		out.push(handle);
		if (out.length === MAX_MENTIONS_PER_COMMENT) break;
	}
	return out;
}

export type MentionSegment =
	| { kind: 'text'; text: string }
	| { kind: 'mention'; text: string; handle: string };

/**
 * The body cut into plain text and mentions, in order, for rendering. Every
 * well-formed mention is a segment (the ten-handle cap is a notification
 * limit, not a display one); whether one renders as a link is the caller's
 * call, once it knows the handle resolves.
 */
export function splitMentions(body: string): MentionSegment[] {
	const out: MentionSegment[] = [];
	let last = 0;
	for (const m of body.matchAll(MENTION)) {
		const at = m.index ?? 0;
		if (at > last) out.push({ kind: 'text', text: body.slice(last, at) });
		out.push({ kind: 'mention', text: m[0], handle: m[1].toLowerCase() });
		last = at + m[0].length;
	}
	if (last < body.length) out.push({ kind: 'text', text: body.slice(last) });
	return out;
}

/**
 * The mention being typed at `caret`, if any: the `@` it starts at and the
 * handle prefix after it (possibly empty). Null when the caret is not inside
 * an `@token` that could still become a mention.
 */
export function activeMentionQuery(
	text: string,
	caret: number,
): { start: number; query: string } | null {
	const before = text.slice(0, Math.max(0, Math.min(caret, text.length)));
	const m = /(?<![A-Za-z0-9_@])@([A-Za-z0-9_]{0,30})$/.exec(before);
	if (!m) return null;
	return { start: m.index, query: m[1].toLowerCase() };
}

/** Replace the `@query` at `start`..`caret` with `@handle ` and return the new text and caret. */
export function insertMention(
	text: string,
	start: number,
	caret: number,
	handle: string,
): { text: string; caret: number } {
	const inserted = `@${handle} `;
	const rest = text.slice(caret).replace(/^[A-Za-z0-9_]*/, '').replace(/^ /, '');
	return { text: text.slice(0, start) + inserted + rest, caret: start + inserted.length };
}
