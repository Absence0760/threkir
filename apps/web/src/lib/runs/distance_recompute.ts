import { METADATA_KEYS } from '../core/schema';
import type { JsonObject, Run, RunSource } from '../types';

/// Sources whose distance one of our own recorders computed from the GPS
/// track it stored, so the server can recompute it from that same track. An
/// import (strava, garmin, healthkit, healthconnect, parkrun, race) carries a
/// distance some other system decided, and a recompute would overwrite it
/// with ours. Keep in step with the source set the job_worker's
/// distance_recompute handler accepts.
export const RECOMPUTABLE_SOURCES: readonly RunSource[] = ['app', 'watch'];

/// The estimator a recompute applies (docs/features/gps_distance.md): spec
/// v1.3's smoother. A run already carrying it has nothing to gain; a run a
/// recompute stamped `kalman_v2` (spec v1.2's smoother) or `kalman_v1` (spec
/// v1.1's forward filter) is offered again.
export const CURRENT_DISTANCE_ESTIMATOR = 'kalman_v3';

export type RecomputeCandidate = Pick<Run, 'user_id' | 'source' | 'track_url' | 'metadata'>;

/// Whether the viewer may offer "Recalculate distance" on this run: they own
/// it and it is a run the server recompute would actually rewrite. The rule
/// past ownership mirrors `distanceRecomputeSkipReason` in
/// apps/job_worker/internal/handler_distance_recompute.go exactly — the
/// worker re-checks it and completes a refused job silently, so a button this
/// side offers that the worker would skip is a no-op the runner cannot see.
/// Change the two together. On top of the worker's rule, a run already on the
/// current estimator is not offered: the worker would accept it, but a replay
/// through the same smoother has nothing to gain.
export function canRecomputeDistance(
	run: RecomputeCandidate | null | undefined,
	viewerId: string | null | undefined,
): boolean {
	if (!run || !viewerId || run.user_id !== viewerId) return false;
	if (!run.track_url) return false;
	if (!RECOMPUTABLE_SOURCES.includes(run.source)) return false;
	const metadata = run.metadata ?? {};
	if (metadata[METADATA_KEYS.in_progress] === true) return false;
	if (metadata[METADATA_KEYS.manual_entry] === true) return false;
	if (metadata[METADATA_KEYS.indoor] === true) return false;
	if (metadata[METADATA_KEYS.indoor_estimated] === true) return false;
	// Any provenance tag names a non-GPS distance (pedometer, treadmill), and
	// an unknown one is not the estimator's to overwrite.
	const distanceSource = metadata[METADATA_KEYS.distance_source];
	if (typeof distanceSource === 'string' && distanceSource !== '') return false;
	// Stamped live by a recorder that ran the estimator over every fix (the
	// watches stamp `kalman_v1`) and never recomputed: the stored track is
	// movement-gated, so a replay would see fewer fixes than the live figure.
	if (
		METADATA_KEYS.distance_estimator in metadata &&
		!(METADATA_KEYS.distance_recomputed_at in metadata)
	) {
		return false;
	}
	if (metadata[METADATA_KEYS.distance_estimator] === CURRENT_DISTANCE_ESTIMATOR) return false;
	return true;
}

/// The recorder's original distance a recompute kept aside, or null when the
/// run was never recomputed (or the value is unusable).
export function recordedDistanceM(metadata: JsonObject | null | undefined): number | null {
	const raw = metadata?.[METADATA_KEYS.distance_recorded_m];
	return typeof raw === 'number' && Number.isFinite(raw) && raw > 0 ? raw : null;
}

/// The run's length along the road graph the map_match job measured for a
/// road run (metadata.distance_map_matched_m), or null when it has none.
/// Display-only: it never replaces distance_m.
export function mapMatchedDistanceM(metadata: JsonObject | null | undefined): number | null {
	const raw = metadata?.[METADATA_KEYS.distance_map_matched_m];
	return typeof raw === 'number' && Number.isFinite(raw) && raw > 0 ? raw : null;
}

export type RecomputeFailure = 'not_authorized' | 'no_track' | 'other';

/// Maps the RPC's typed refusals (42501 not the owner, 22000 no stored track)
/// to the message the page shows; anything else is shown as a generic failure
/// carrying the server's own text.
export function classifyRecomputeError(error: unknown): RecomputeFailure {
	const code = (error as { code?: unknown } | null)?.code;
	if (code === '42501') return 'not_authorized';
	if (code === '22000') return 'no_track';
	return 'other';
}
