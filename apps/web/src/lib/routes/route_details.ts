// The owner's edit of a route's name and description on /routes/[id].
// Pure, so the rules are unit-tested without a Supabase stack;
// `updateRouteDetails` in `core/data.ts` does the write.

import { lengthLimit } from '../core/column_limits';
import { officialDistanceVerdict } from './official_distance';

export type RouteDetails = { name: string; description: string | null };

export type RouteDetailsPatch = {
	name?: string;
	description?: string | null;
	official_distance_m?: number | null;
};

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

export type OfficialDistanceInput =
	| { kind: 'unchanged' }
	| { kind: 'set'; officialM: number | null }
	| { kind: 'notANumber' }
	| { kind: 'outOfRange' }
	| { kind: 'tooFar' };

/// The official distance the owner typed, in [unitM] metres per unit (1000 for
/// km, 1609.344 for mi), read against the route's [measuredM] and the value
/// it [loadedM] with. Blank clears it. A comma decimal is accepted, since most
/// of the locales the app ships write one. Stored to the decimetre, so a half
/// marathon keeps its 21,097.5 m.
export function parseOfficialDistanceInput(
	text: string,
	unitM: number,
	measuredM: number,
	loadedM: number | null,
): OfficialDistanceInput {
	const trimmed = text.trim().replace(',', '.');
	if (trimmed === '') return loadedM == null ? { kind: 'unchanged' } : { kind: 'set', officialM: null };
	const value = Number(trimmed);
	if (!Number.isFinite(value)) return { kind: 'notANumber' };
	// The field shows the stored value rounded to three decimals of a unit, so
	// saving it back untouched must not write the rounding (26.219 mi is not
	// the 42,195 m it was opened on).
	if (loadedM != null && value === Number(officialDistanceInputValue(loadedM, unitM))) {
		return { kind: 'unchanged' };
	}
	const officialM = Math.round(value * unitM * 10) / 10;
	const verdict = officialDistanceVerdict(measuredM, officialM);
	if (verdict !== 'ok') return { kind: verdict };
	return { kind: 'set', officialM };
}

/// The value the edit field opens with: the stored official distance in the
/// viewer's unit, to three decimals with trailing zeros dropped (42.195).
export function officialDistanceInputValue(officialM: number | null, unitM: number): string {
	if (officialM == null) return '';
	return String(Number((officialM / unitM).toFixed(3)));
}
