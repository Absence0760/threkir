/// Pure dedupe-key helper for the Garmin bulk importer, split out of
/// `garmin-zip.ts` so it can be unit-tested without pulling in that
/// module's Svelte / Supabase dependency graph.

import { KEYSET_WALK_PAGE_SIZE, walkKeyset, type KeysetKey } from '../core/keyset_page';

/// Canonical dedupe key for the `started_at + distance` fallback path.
/// The three sources that feed the importer's `seenComposite` set format
/// these fields differently — the DB serialises `started_at` as a
/// timestamptz (`2026-01-01T09:00:00+00:00`) while parsed imports carry a
/// `Z`-suffixed ISO string, and distances arrive as floats from the DB
/// but rounded ints from the GPX/TCX path. Left un-normalised the same
/// logical run never matched itself across a re-import, so every GPX/TCX
/// re-import duplicated. Normalise both (parse → toISOString, round
/// metres) so all three paths produce the same key.
export function compositeKey(startedAt: string, distanceM: number | null | undefined): string {
	const parsed = Date.parse(startedAt);
	const ts = Number.isFinite(parsed) ? new Date(parsed).toISOString() : startedAt;
	return `${ts}|${Math.round(distanceM ?? 0)}`;
}

/// Cross-provider near-duplicate guard.
///
/// `compositeKey` above only matches EXACT (rounded) start + distance, and
/// the importer's `garmin_id` key only matches the same FIT file. Neither
/// catches the same physical activity that already arrived under another
/// source: a Garmin watch that auto-uploaded to Strava lands a
/// `source='strava'` row, then the user imports the Garmin bulk-export ZIP
/// and the `source='garmin'`-scoped dedupe never sees the Strava row — so the
/// run duplicates. Two recordings of one effort start within seconds and
/// cover ~the same distance; two genuinely distinct runs can't start within a
/// few minutes of each other (you can't record two tracks at once), so we
/// gate on BOTH axes to avoid suppressing a warm-up + race of similar
/// distance but well-separated starts. Keep in lockstep with the Deno twin
/// `isCrossProviderDuplicate` in
/// `apps/backend/supabase/functions/_shared/strava.ts`.

/// A run's identity for cross-provider matching: start instant (epoch ms)
/// and total distance (metres).
export interface RunIdentity {
	startedAtMs: number;
	distanceM: number;
}

/// Max start-time gap (seconds) for two rows to be the same effort.
export const CROSS_PROVIDER_START_TOLERANCE_S = 180;
/// Max relative distance difference for two rows to be the same effort.
export const CROSS_PROVIDER_DISTANCE_FRACTION = 0.05;

/// True when `candidate` is a near-duplicate of any row in `existing` —
/// start within the tolerance AND distance within the fraction.
export function isCrossProviderDuplicate(
	candidate: RunIdentity,
	existing: readonly RunIdentity[],
): boolean {
	if (!Number.isFinite(candidate.startedAtMs)) return false;
	for (const row of existing) {
		if (!Number.isFinite(row.startedAtMs) || !Number.isFinite(row.distanceM)) continue;
		const dtS = Math.abs(candidate.startedAtMs - row.startedAtMs) / 1000;
		if (dtS > CROSS_PROVIDER_START_TOLERANCE_S) continue;
		const larger = Math.max(Math.abs(candidate.distanceM), Math.abs(row.distanceM));
		const diff = Math.abs(candidate.distanceM - row.distanceM);
		if (larger === 0 || diff <= larger * CROSS_PROVIDER_DISTANCE_FRACTION) return true;
	}
	return false;
}

/// A raw `{ id, started_at, distance_m }` row as PostgREST returns it; `id`
/// and `started_at` are the walk's cursor.
export interface RawRunRow {
	id: string;
	started_at: string | null;
	distance_m: number | null;
}

/// The order both ZIP importers walk the existing runs in: newest first, `id`
/// breaking a `started_at` tie so the order is total. Both NOT NULL.
export const RUN_DEDUPE_ORDER: readonly KeysetKey[] = [
	{ column: 'started_at', ascending: false, nullsFirst: true },
	{ column: 'id', ascending: false, nullsFirst: true },
];

/// One keyset page of the existing runs: apply `after` (null on the first
/// page), sort by `RUN_DEDUPE_ORDER`, take `limit`.
export type DedupePage<R> = (
	after: string | null,
	limit: number,
) => PromiseLike<{ data: R[] | null; error: unknown }>;

/// Pull every existing run's start + distance identity across ALL sources.
/// PostgREST caps an unbounded SELECT at 1000 rows, which for the high-volume
/// pros the cross-provider guard exists to protect (1000+ runs) would compare
/// against an arbitrary slice and re-import duplicates anyway — so the read
/// is walked, and walked by keyset cursor: an OFFSET walk over a history that
/// a sync changes mid-import drops a row at a page boundary, and a dropped
/// identity is a run imported twice (§ 1927). A page error ends the walk with
/// what it has rather than throwing, as it always has.
export async function collectRunIdentities(
	fetchPage: DedupePage<RawRunRow>,
	pageSize: number = KEYSET_WALK_PAGE_SIZE,
): Promise<RunIdentity[]> {
	const walk = await walkKeyset(RUN_DEDUPE_ORDER, fetchPage, { pageSize });
	if (!walk.complete) console.warn('collectRunIdentities: the walk ended short', walk.error);
	const out: RunIdentity[] = [];
	for (const r of walk.rows) {
		const ms = Date.parse(r.started_at ?? '');
		if (!Number.isFinite(ms)) continue;
		out.push({ startedAtMs: ms, distanceM: Number(r.distance_m ?? 0) });
	}
	return out;
}
