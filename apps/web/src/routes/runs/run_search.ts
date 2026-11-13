import { fold } from '#lib/segments/catalogue_browse.ts';

/// Whether a run's name matches the `/runs` search: the runner's own caption
/// (`runs.metadata.title`), compared case- and accent-insensitively through
/// the catalogue's `fold`, as mobile's Runs search does. A blank query matches
/// every run; a run with no name never matches a non-blank one.
export function runMatchesQuery(metadata: unknown, query: string): boolean {
	const q = fold(query.trim());
	if (q === '') return true;
	const title = metadata && typeof metadata === 'object' ? (metadata as { title?: unknown }).title : undefined;
	return typeof title === 'string' && fold(title).includes(q);
}
