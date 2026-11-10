/**
 * Searching the viewer's own direct messages (issue #1216, migration
 * 20271213121603). `search_direct_messages` runs under the caller's own RLS;
 * this only shapes the query and the snippet. Mobile twin: `dm_search.dart`.
 */

/** The query length the RPC accepts, in characters. */
export const DM_SEARCH_MIN_CHARS = 2;
export const DM_SEARCH_MAX_CHARS = 100;

/** The query as the server will read it, or null when it would match nothing. */
export function normalizeDmSearchQuery(raw: string): string | null {
	const q = raw.trim();
	const n = [...q].length;
	return n >= DM_SEARCH_MIN_CHARS && n <= DM_SEARCH_MAX_CHARS ? q : null;
}

export interface DmSearchSnippet {
	before: string;
	match: string;
	after: string;
}

/**
 * The part of `body` around the first case-insensitive match of `query`,
 * with up to `radius` characters each side and an ellipsis where text was
 * cut. A body with no match (the server and the client case-fold
 * differently for a few scripts) is shown from its start.
 */
export function dmSearchSnippet(body: string, query: string, radius = 40): DmSearchSnippet {
	const chars = [...body];
	const lower = chars.map((c) => c.toLowerCase());
	const needle = [...query.trim()].map((c) => c.toLowerCase());
	let at = -1;
	if (needle.length > 0) {
		for (let i = 0; i + needle.length <= lower.length; i++) {
			let hit = true;
			for (let j = 0; j < needle.length; j++) {
				if (lower[i + j] !== needle[j]) {
					hit = false;
					break;
				}
			}
			if (hit) {
				at = i;
				break;
			}
		}
	}
	if (at < 0) {
		const head = chars.slice(0, radius * 2);
		return { before: '', match: '', after: head.join('') + (chars.length > head.length ? '…' : '') };
	}
	const start = Math.max(0, at - radius);
	const end = Math.min(chars.length, at + needle.length + radius);
	return {
		before: (start > 0 ? '…' : '') + chars.slice(start, at).join(''),
		match: chars.slice(at, at + needle.length).join(''),
		after: chars.slice(at + needle.length, end).join('') + (end < chars.length ? '…' : ''),
	};
}
