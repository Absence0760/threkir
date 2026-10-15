/// A route's tags as the set they are: NULL elements dropped, each value kept
/// at its first position, exact equality.
///
/// The same canonical form as `private.distinct_text_array`, which the
/// `routes_tags_distinct` trigger applies to every write (migration
/// 20270816000011). Reading through it as well keeps every keyed
/// `{#each … (t)}` over tags safe against a row written before that migration,
/// or a mock / restored object that never went through the database — one
/// duplicate there throws each_key_duplicate and takes the page down.
export function distinctTags(tags: readonly (string | null)[] | null | undefined): string[] {
	if (!tags) return [];
	const seen = new Set<string>();
	for (const t of tags) {
		if (typeof t === 'string') seen.add(t);
	}
	return [...seen];
}
