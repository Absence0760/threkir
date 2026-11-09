/// Pure normalisation helpers used by `data.ts`. Lifted into their own
/// module so the trim-and-null contract can be unit-tested without
/// pulling in the Supabase client (which `data.ts` imports at top
/// level and can't safely run under `node:test`).
///
/// Every helper mirrors the JS `s?.trim() || null` pattern used
/// throughout `data.ts`. Dart-side counterparts live in
/// `apps/mobile_android/lib/social_service.dart` (`buildCreateClubBody`,
/// `buildCreateEventBody`) and `apps/mobile_android/lib/training_service.dart`
/// (`trimToNull`); the test suites on both sides pin the same
/// edge cases (null / empty / whitespace / "0" truthiness / emoji).

import { METADATA_KEYS } from './schema';
import type { JsonObject, TrackPoint } from '../types';

/// Trim a string and collapse empty-after-trim to null. Mirrors
/// `s?.trim() || null`. Pulled out so it can be reused without the
/// `||` truthiness ambiguity at every call site.
export function trimOrNull(s: string | null | undefined): string | null {
	if (s == null) return null;
	const t = s.trim();
	return t.length > 0 ? t : null;
}

/// Normalise the `fields` patch handed to `updateRunMetadata`.
/// Trims every string value; empty-after-trim keys are dropped from
/// the patch entirely (so clearing the field via the run-detail edit
/// dialog actually removes the metadata key rather than leaving a
/// stale `""` behind).
///
/// Returns a partial object; callers spread it into the existing
/// metadata bag with the cleared keys explicitly deleted beforehand.
export function normaliseRunMetadataFields(fields: {
	title?: string;
	notes?: string;
}): { title?: string; notes?: string } {
	const out: { title?: string; notes?: string } = {};
	for (const key of ['title', 'notes'] as const) {
		const value = fields[key];
		if (typeof value !== 'string') continue;
		const trimmed = value.trim();
		if (trimmed.length > 0) out[key] = trimmed;
	}
	return out;
}

/// Apply an `updateRunMetadata` patch on top of an existing metadata
/// bag with the cleared keys explicitly removed. Returns the new
/// metadata object. Pure — no I/O. Tests pin the contract.
export function applyRunMetadataPatch(
	current: JsonObject | null | undefined,
	fields: { title?: string; notes?: string },
): JsonObject {
	const base = current ?? {};
	const next: JsonObject = { ...base };
	// Drop any key the caller is patching, then re-add normalised
	// values. This is how a whitespace-only edit clears the key
	// instead of writing `""`.
	for (const key of Object.keys(fields)) {
		delete next[key];
	}
	Object.assign(next, normaliseRunMetadataFields(fields));
	return next;
}

/// Row cap on a whole-catalogue read: the DEFAULT of `fetchGlobalSegments`
/// and `fetchGlobalSegmentsWithError`, so the `/segments` browse page and
/// every other caller that omits the argument agree on what "the catalogue"
/// means. Scoring no longer reads the whole catalogue: it asks for the
/// segments near a track (`GLOBAL_SEGMENT_CANDIDATE_LIMIT`, decisions § 2392).
export const GLOBAL_SEGMENT_SCORING_LIMIT = 500;

/// Cap on the candidates one track is scored against (`global_segments_in_bbox`).
/// A track meets a handful of segments; this only bounds a pathological
/// catalogue. The same figure as CANDIDATE_LIMIT in the `segment-match` Edge
/// Function, so the fallback and the server score the same set.
export const GLOBAL_SEGMENT_CANDIDATE_LIMIT = 1000;

/// Metres the track's extent is padded by when asking for candidates, above
/// the matcher's 35 m tolerance so no segment it could time is missed. The
/// same figure as CANDIDATE_PAD_M in the `segment-match` Edge Function.
export const GLOBAL_SEGMENT_CANDIDATE_PAD_M = 50;

/// The `runs.metadata.global_segments_scored_count` stamp: the number
/// of active `global_segments` a run's catalogue efforts were last
/// computed against. Lets the run-detail backfill skip the expensive
/// catalogue fetch + client-side haversine match on every view once a
/// run is scored, while still re-scoring when the (deliberately
/// growing) catalogue gains segments. Value-only (no view timestamp) so
/// the key carries no per-run private signal — the catalogue size is
/// identical for every run and public — and needs no `public_runs`
/// strip.
export function readGlobalSegmentsScoredCount(
	metadata: JsonObject | null | undefined,
): number | null {
	if (!metadata || typeof metadata !== 'object') return null;
	const count = metadata[METADATA_KEYS.global_segments_scored_count];
	if (typeof count !== 'number' || !Number.isFinite(count) || count < 0) return null;
	return count;
}

/// The `runs.metadata.global_segments_matcher_version` stamp: the catalogue
/// matcher version (`GLOBAL_SEGMENT_MATCHER_VERSION`) a run's efforts were
/// last computed by. A run scored before the stamp existed carries only the
/// count, and was scored by version 1 (the circles-only matcher); a run never
/// scored reads null.
export function readGlobalSegmentsMatcherVersion(
	metadata: JsonObject | null | undefined,
): number | null {
	if (!metadata || typeof metadata !== 'object') return null;
	const version = metadata[METADATA_KEYS.global_segments_matcher_version];
	if (typeof version === 'number' && Number.isInteger(version) && version >= 1) return version;
	return readGlobalSegmentsScoredCount(metadata) == null ? null : 1;
}

/// Decide whether a run needs its global-segment efforts (re)computed.
/// True when the run was never scored, when the stamp is unreadable, when
/// the run was scored by an older matcher than `matcherVersion` (its efforts
/// are then re-matched, issue #1308), or when the active catalogue has grown
/// past the count the run was last scored against. `activeCount` null (an
/// unknown / failed count query) fails open to true — better to re-score once
/// than to never score a run whose catalogue size we couldn't read.
///
/// The stamp is the active count the pass ran under, not the size of a
/// capped fetch, so it can always reach the count it is compared with. A
/// run stamped 500 by the old capped fetch under a larger catalogue is
/// re-scored once, which is right: it was never scored against the tail.
export function shouldRescoreGlobalSegments(
	metadata: JsonObject | null | undefined,
	activeCount: number | null | undefined,
	matcherVersion: number,
): boolean {
	const scored = readGlobalSegmentsScoredCount(metadata);
	if (scored == null) return true;
	const version = readGlobalSegmentsMatcherVersion(metadata);
	if (version == null || version < matcherVersion) return true;
	if (typeof activeCount !== 'number' || !Number.isFinite(activeCount)) return true;
	return activeCount > scored;
}

/// Merge the `global_segments_scored_count` and
/// `global_segments_matcher_version` stamps into a run's metadata bag without
/// clobbering the rest of it. Pure — the caller writes the result back.
export function stampGlobalSegmentsScored(
	metadata: JsonObject | null | undefined,
	catalogueCount: number,
	matcherVersion: number,
): JsonObject {
	const base = metadata ?? {};
	return {
		...base,
		[METADATA_KEYS.global_segments_scored_count]: catalogueCount,
		[METADATA_KEYS.global_segments_matcher_version]: matcherVersion,
	};
}

/// Normalise the `notes` field of a plan-workout update patch. Trims
/// and collapses empty-after-trim to null. Caller is responsible for
/// only invoking this when `notes` is present in the patch.
export function normalisePlanWorkoutNotes(
	value: string | null | undefined,
): string | null | undefined {
	if (value == null) return value;
	const t = value.trim();
	return t.length > 0 ? t : null;
}

/// Collapse a PostgREST embedded relation to the single row it represents.
///
/// A `select('…, clubs(slug)')` embed comes back as an OBJECT when PostgREST
/// can prove the relationship is to-one and as an ARRAY when it cannot — and
/// which of the two you get depends on the FK metadata it detects, not on
/// anything in the query. Four sites in `data.ts` read the same
/// `events → clubs` embed; three normalised, and the fourth
/// (`fetchNextRsvpedEvent`) read `ev.clubs.slug` straight through, so an array
/// shape would have put `undefined` into a `club_slug` typed `string` and
/// deep-linked the dashboard card at `/clubs/undefined/events/…`.
///
/// An empty array and a null embed both mean "no related row" and both answer
/// null; the caller decides whether that is a skip or a fallback.
export function singleEmbed<T>(value: T | T[] | null | undefined): T | null {
	if (Array.isArray(value)) return value[0] ?? null;
	return value ?? null;
}

/// Whether a fitness snapshot is owed for the calendar day `now` falls in,
/// given the `computed_at` of the runner's most recent one (null when they
/// have none).
///
/// `/dashboard` recomputes the snapshot on every mount and persisted it every
/// time, so a runner who opens the dashboard three or four times a day filled
/// the trend chart's 60-point window with same-day duplicates inside about two
/// and a half weeks and the real multi-month trend scrolled off the left.
///
/// The day is measured in UTC on purpose: the uniqueness this pairs with is a
/// database constraint over `computed_at`, and a `date` cast there runs in the
/// connection's time zone, which is UTC for PostgREST. Comparing local days
/// would put the client and the constraint on different calendars near
/// midnight.
///
/// Fails CLOSED — an unreadable or unparseable timestamp answers "not owed".
/// The two mistakes are not symmetric: skipping a write loses one day's point
/// from a chart that self-heals tomorrow, while writing when unsure is the
/// duplicate-spam this exists to stop.
export function fitnessSnapshotDue(
	latestComputedAt: string | null | undefined,
	now: Date,
): boolean {
	const nowMs = now.getTime();
	if (!Number.isFinite(nowMs)) return false;
	if (latestComputedAt == null) return true;
	const latest = new Date(latestComputedAt);
	if (!Number.isFinite(latest.getTime())) return false;
	return (
		latest.getUTCFullYear() !== now.getUTCFullYear() ||
		latest.getUTCMonth() !== now.getUTCMonth() ||
		latest.getUTCDate() !== now.getUTCDate()
	);
}

/// The columns `ROUTE_LIST_COLS` selects off the base `routes` table that the
/// `public_routes` view has no counterpart for, filled with the value that
/// means "withheld here" — one object rather than a cast that asserts the
/// narrow row is already the wide type.
///
/// `waypoints: []` is not "this route has no line". It is the signal
/// `RouteTrackPreview` already reads as "fetch this viewer's clipped line",
/// which is the shape the RouteExplorer cards pass and the only correct one
/// here: `public_routes` withholds the polyline on purpose, because a
/// non-owner's line is served only through `clip_route_for_viewer` with the
/// owner's privacy zones removed (decisions § 33). Casting instead left
/// `waypoints` `undefined` under a type declaring `TrackPoint[]`, so the
/// routes list gated its thumbnail on a field that could not be there and
/// every route saved from Explore — the dominant case — rendered a grey
/// placeholder.
///
/// `is_starred: false` is the truth, not a placeholder: the star is the
/// OWNER's flag on their own row, and every row from this view belongs to
/// somebody else.
export function publicRouteListFill(): {
	waypoints: TrackPoint[];
	is_starred: boolean;
} {
	return { waypoints: [], is_starred: false };
}
