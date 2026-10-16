// Run reactions (decisions § 1971). TS↔Dart parity pair with
// apps/mobile_android/lib/run_reactions.dart. The key list is the client rail
// of the run_reactions_reaction_check CHECK (check_constraint_unions.mjs).
// Keys are stable strings, never emoji; each renders as an icon that is
// already in the shipped Material Symbols subset.

export const REACTION_KEYS = ['fire', 'strong', 'trophy', 'thumbs_up', 'wave'] as const;
export type ReactionKey = (typeof REACTION_KEYS)[number];

export const REACTION_ICONS: Record<ReactionKey, string> = {
	fire: 'local_fire_department',
	strong: 'fitness_center',
	trophy: 'emoji_events',
	thumbs_up: 'thumb_up',
	wave: 'waving_hand',
};

export function isReactionKey(v: unknown): v is ReactionKey {
	return typeof v === 'string' && (REACTION_KEYS as readonly string[]).includes(v);
}

export interface ReactionTally {
	key: ReactionKey;
	count: number;
	viewerReacted: boolean;
}

/**
 * One tally per whitelisted key, in whitelist order, from the summary RPC's
 * rows. A key nobody used reads zero; a row naming a key this client does not
 * know (a newer server) is dropped rather than drawn without an icon.
 */
export function reactionTallies(
	rows: readonly { reaction: string; reaction_count: number; viewer_reacted: boolean }[],
): ReactionTally[] {
	const byKey = new Map<string, { count: number; viewer: boolean }>();
	for (const r of rows) {
		if (!isReactionKey(r.reaction)) continue;
		byKey.set(r.reaction, {
			count: Math.max(0, Math.floor(Number(r.reaction_count) || 0)),
			viewer: r.viewer_reacted === true,
		});
	}
	return REACTION_KEYS.map((key) => ({
		key,
		count: byKey.get(key)?.count ?? 0,
		viewerReacted: byKey.get(key)?.viewer ?? false,
	}));
}

/**
 * The tallies after the viewer toggled `key`. `changed` is whether the server
 * actually inserted / deleted a row: a no-op (the state already matched, from
 * another tab) flips the flag without moving the count, so the total cannot
 * drift from the server's.
 */
export function applyReactionToggle(
	tallies: readonly ReactionTally[],
	key: ReactionKey,
	nowReacted: boolean,
	changed: boolean,
): ReactionTally[] {
	return tallies.map((t) => {
		if (t.key !== key) return t;
		const delta = changed ? (nowReacted ? 1 : -1) : 0;
		return { key, count: Math.max(0, t.count + delta), viewerReacted: nowReacted };
	});
}
