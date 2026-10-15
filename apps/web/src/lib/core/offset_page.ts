// Appending an offset-paginated "load more" page to the rows already shown.
//
// Pure — no Svelte / Supabase dependencies, so it runs under `npx tsx --test`.

/// `shown` followed by the rows of `page` not already in it, compared on
/// `keyOf`. An offset is a position, not a row, so whenever the list changes
/// between two reads the next page overlaps the last: a new follower lands at
/// the top of a newest-first list and pushes the previous page's last row
/// into the next one; a member who leaves and rejoins moves to the end of an
/// oldest-first roster they were already on. Appended blindly, the overlap
/// renders the same row twice — and a keyed `{#each}` throws
/// `each_key_duplicate` and takes the page down. The row already on screen
/// keeps its place.
///
/// Callers keep deciding "is there more?" from the raw page length: a page
/// that was all overlap is still a full page of the server's list.
export function appendPage<T>(
	shown: readonly T[],
	page: readonly T[],
	keyOf: (row: T) => string,
): T[] {
	const seen = new Set(shown.map(keyOf));
	const out = [...shown];
	for (const row of page) {
		const key = keyOf(row);
		if (seen.has(key)) continue;
		seen.add(key);
		out.push(row);
	}
	return out;
}
