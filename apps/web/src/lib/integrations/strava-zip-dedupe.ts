/// Pure helper for the Strava ZIP importer — kept in its own file so
/// `npx tsx --test` can exercise it without dragging in the SvelteKit
/// `$app/env` chain that `strava-zip.ts` imports via supabase.ts.
///
/// Persona-hunt finding Intermediate #1: pre-fix the importer queried
/// only `source='strava'` + metadata.strava_id, so older rows from
/// before the strava_id tag was added — or rows that lost the
/// metadata key during a partial restore — slipped past the dedup
/// and re-imported as silent duplicates. The fix pulls IDs from BOTH
/// the canonical metadata.strava_id (set by every modern path) AND
/// the external_id column (`strava:<id>` set by every path including
/// the EF backfill + the mobile importer). Also drops the
/// `source='strava'` filter — a Strava activity re-saved by another
/// path still dedupes against its strava:<id> key.
import { KEYSET_WALK_PAGE_SIZE, walkKeyset } from '../core/keyset_page';
import { RUN_DEDUPE_ORDER, type DedupePage } from './garmin_dedupe';

export type StravaDedupeRow = { metadata?: unknown; external_id?: string | null };

/// A dedupe row as the walk reads it: `id` and `started_at` are its cursor.
export type StravaDedupeWalkRow = StravaDedupeRow & { id: string; started_at: string };

export function buildStravaDedupeSet(rows: StravaDedupeRow[]): Set<string> {
	const seen = new Set<string>();
	for (const r of rows) {
		const sid = (r.metadata as Record<string, unknown> | null)?.strava_id;
		if (sid) seen.add(String(sid));
		const extId = r.external_id;
		if (extId && extId.startsWith('strava:')) {
			seen.add(extId.slice('strava:'.length));
		}
	}
	return seen;
}

/// Walk the existing runs before building the dedupe set. An unbounded
/// PostgREST SELECT caps at 1000 rows, so a 1000+-run migrant re-importing a
/// refreshed ZIP would otherwise dedupe against an arbitrary slice and
/// silently re-import everything past the cap. Walked by keyset cursor in
/// `RUN_DEDUPE_ORDER`, not by OFFSET: a row dropped at a page boundary by a
/// concurrent sync or delete is an id missing from the set, which re-imports
/// the activity (§ 1936). A page error ends the walk with what it has rather
/// than throwing. Pure + injectable so `npx tsx --test` can exercise it.
export async function collectStravaDedupeSet(
	fetchPage: DedupePage<StravaDedupeWalkRow>,
	pageSize: number = KEYSET_WALK_PAGE_SIZE,
): Promise<Set<string>> {
	const walk = await walkKeyset(RUN_DEDUPE_ORDER, fetchPage, { pageSize });
	if (!walk.complete) console.warn('collectStravaDedupeSet: the walk ended short', walk.error);
	return buildStravaDedupeSet(walk.rows);
}
