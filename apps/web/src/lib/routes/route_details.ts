// The owner's edit of a route's name and description on /routes/[id].
// Pure, so the rules are unit-tested without a Supabase stack;
// `updateRouteDetails` in `core/data.ts` does the write.

import { lengthLimit } from '../core/column_limits';

export type RouteDetails = { name: string; description: string | null };

export type RouteDetailsPatch = { name?: string; description?: string | null };

export type RouteDetailsResult =
	| { kind: 'patch'; patch: RouteDetailsPatch }
	| { kind: 'unchanged' }
	| { kind: 'nameRequired' }
	| { kind: 'tooLong'; field: 'name' | 'description' };

/// The UPDATE body for [draft] typed over [loaded]. Only a field whose
/// trimmed value differs is written, so renaming never writes back a
/// description another device changed since this page loaded. A blank
/// description is stored as null, the column's "none" state, which brings
/// back the page's "Describe this route" button; a blank name is refused
/// because `routes.name` is not null.
export function routeDetailsPatch(loaded: RouteDetails, draft: RouteDetails): RouteDetailsResult {
	const name = draft.name.trim();
	const description = (draft.description ?? '').trim() || null;
	if (!name) return { kind: 'nameRequired' };
	if (name.length > lengthLimit('routes.name')) return { kind: 'tooLong', field: 'name' };
	if (description && description.length > lengthLimit('routes.description')) {
		return { kind: 'tooLong', field: 'description' };
	}
	const patch: RouteDetailsPatch = {};
	if (name !== loaded.name) patch.name = name;
	if (description !== (loaded.description?.trim() || null)) patch.description = description;
	return Object.keys(patch).length === 0 ? { kind: 'unchanged' } : { kind: 'patch', patch };
}
