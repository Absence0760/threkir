// Badge awards from people you follow, placed in the following feed as
// compact chronological rows instead of a sideways strip (issue #1374).
// TS↔Dart parity pair with
// apps/mobile_android/lib/feed_highlights.dart — keep the algorithm, edge
// cases and test counts in lockstep.
//
// Two cursor-paged streams meet here: the activity feed (started_at desc) and
// the badge awards (earned_at desc). A highlight is only placed once the
// activity page reaches back past it, so it never sits under the last loaded
// card while older activity has yet to load, and the badge stream is read on
// until it reaches back as far as the activity has.

/** The slice of a badge award the grouping reads. */
export interface HighlightAward {
	authorId: string;
	badge: { id: string; earned_at: string };
}

/** One person's awards on one local day, newest first. */
export interface FeedHighlight<A extends HighlightAward> {
	/** `${authorId}|${day}`. */
	key: string;
	authorId: string;
	awards: A[];
	/** The newest award's `earned_at`, where the row sits in the feed. */
	at: string;
}

export type FeedRow<E, A extends HighlightAward> =
	| { kind: 'entry'; entry: E }
	| { kind: 'highlight'; highlight: FeedHighlight<A> };

/** The viewer's local calendar day of an ISO instant. */
export function localDayKey(iso: string): string {
	const d = new Date(iso);
	return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

/** Highlights are not an activity, so a chip naming one hides them. */
export function highlightsShowFor(activityFilter: string): boolean {
	return activityFilter === 'all';
}

function newerFirst(a: HighlightAward, b: HighlightAward): number {
	const ta = Date.parse(a.badge.earned_at);
	const tb = Date.parse(b.badge.earned_at);
	if (ta !== tb) return tb - ta;
	return a.badge.id < b.badge.id ? 1 : a.badge.id > b.badge.id ? -1 : 0;
}

/**
 * Collapse awards into one highlight per (person, local day), newest first.
 * An award seen twice (an overlapping page) counts once.
 */
export function groupHighlights<A extends HighlightAward>(
	awards: readonly A[],
	dayKey: (iso: string) => string = localDayKey
): FeedHighlight<A>[] {
	const seen = new Set<string>();
	const unique = awards.filter((a) => (seen.has(a.badge.id) ? false : (seen.add(a.badge.id), true)));
	const sorted = [...unique].sort(newerFirst);
	const byKey = new Map<string, FeedHighlight<A>>();
	for (const a of sorted) {
		const key = `${a.authorId}|${dayKey(a.badge.earned_at)}`;
		const group = byKey.get(key);
		if (group) group.awards.push(a);
		else byKey.set(key, { key, authorId: a.authorId, awards: [a], at: a.badge.earned_at });
	}
	return [...byKey.values()];
}

/**
 * The feed as one vertical list: activity entries in their order, each
 * highlight placed by its newest award. While more activity can still load,
 * a highlight older than the oldest loaded entry waits for that page.
 * At an equal instant the activity entry comes first.
 */
export function interleaveHighlights<E, A extends HighlightAward>(
	entries: readonly E[],
	entryAt: (e: E) => string,
	highlights: readonly FeedHighlight<A>[],
	feedExhausted: boolean
): FeedRow<E, A>[] {
	if (!feedExhausted && entries.length === 0) return [];
	const floor = feedExhausted ? null : Date.parse(entryAt(entries[entries.length - 1]));
	const placed = highlights.filter((h) => floor === null || Date.parse(h.at) >= floor);
	const rows: FeedRow<E, A>[] = [];
	let h = 0;
	for (const entry of entries) {
		const t = Date.parse(entryAt(entry));
		while (h < placed.length && Date.parse(placed[h].at) > t) {
			rows.push({ kind: 'highlight', highlight: placed[h++] });
		}
		rows.push({ kind: 'entry', entry });
	}
	while (h < placed.length) rows.push({ kind: 'highlight', highlight: placed[h++] });
	return rows;
}

/**
 * Whether the badge stream must read another page before the rows are
 * complete: it has more, and what it has loaded does not yet reach back as
 * far as the activity (or the activity has run out).
 */
export function needsMoreHighlights(opts: {
	oldestAwardAt: string | null;
	awardsExhausted: boolean;
	oldestEntryAt: string | null;
	feedExhausted: boolean;
}): boolean {
	if (opts.awardsExhausted) return false;
	if (opts.oldestAwardAt === null) return true;
	if (opts.feedExhausted || opts.oldestEntryAt === null) return true;
	return Date.parse(opts.oldestAwardAt) >= Date.parse(opts.oldestEntryAt);
}
