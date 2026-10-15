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
/// v1.4's smoother. A run already carrying it has nothing to gain; a run a
/// recompute stamped `kalman_v3` (spec v1.3's smoother), `kalman_v2` (spec
/// v1.2's) or `kalman_v1` (spec v1.1's forward filter) is offered again.
export const CURRENT_DISTANCE_ESTIMATOR = 'kalman_v4';

/// Live stamps of recorders that feed their estimator fixes their track gate
/// refuses (spec v1.4 on): such a run's stored track holds every fix the
/// estimator took only when it says `track_complete`, so a replay of any
/// other would credit each canopy stretch its chord and read short. A spec
/// bump adds its value. Mirrors `trackGatedEstimators` in the job_worker.
export const TRACK_GATED_ESTIMATORS: readonly string[] = ['kalman_v4'];

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
	// Stamped by the phone recorder, which saved the smoother's figure over
	// every fix, and never recomputed: its stored track is movement-gated, so
	// a replay would see fewer fixes than the save did. A watch stamp
	// (`kalman_v1`, the wrist's forward filter) is no bar: the watch stored
	// every fix that filter took, so the replay gains the smoother.
	if (
		run.source !== 'watch' &&
		METADATA_KEYS.distance_estimator in metadata &&
		!(METADATA_KEYS.distance_recomputed_at in metadata)
	) {
		return false;
	}
	// Stamped live by a v1.4 recorder whose track omits the canopy fixes its
	// estimator took. The Wear OS and watchOS builds before track_complete
	// stamp `kalman_v1`, whose track the replay reproduces.
	const estimator = metadata[METADATA_KEYS.distance_estimator];
	const recomputed = METADATA_KEYS.distance_recomputed_at in metadata;
	if (
		!recomputed &&
		typeof estimator === 'string' &&
		TRACK_GATED_ESTIMATORS.includes(estimator) &&
		metadata[METADATA_KEYS.track_complete] !== true
	) {
		return false;
	}
	// A recompute already applied the current smoother. A live stamp names
	// the recorder's forward filter, which the replay improves on.
	if (recomputed && estimator === CURRENT_DISTANCE_ESTIMATOR) return false;
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
