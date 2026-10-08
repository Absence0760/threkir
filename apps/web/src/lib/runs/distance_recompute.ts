import { METADATA_KEYS } from '../core/schema';
import type { JsonObject, Run, RunSource } from '../types';

/// Sources whose distance one of our own recorders computed from the GPS
/// track it stored, so the server can recompute it from that same track. An
/// import (strava, garmin, healthkit, healthconnect, parkrun, race) carries a
/// distance some other system decided, and a recompute would overwrite it
/// with ours. Keep in step with the source set the job_worker's
/// distance_recompute handler accepts.
export const RECOMPUTABLE_SOURCES: readonly RunSource[] = ['app', 'watch'];

/// The estimator a recompute applies (docs/features/gps_distance.md). A run
/// already carrying it has nothing to gain.
export const CURRENT_DISTANCE_ESTIMATOR = 'kalman_v1';

export type RecomputeCandidate = Pick<Run, 'user_id' | 'source' | 'track_url' | 'metadata'>;

/// Whether the viewer may offer "Recalculate distance" on this run: they own
/// it, it has a stored track, one of our recorders wrote it, its distance is
/// not a pedometer estimate (no GPS to recompute from), and it was not already
/// recorded or recomputed with the current estimator. The RPC re-checks the
/// first two server-side; the rest only decide whether the button is useful.
export function canRecomputeDistance(
	run: RecomputeCandidate | null | undefined,
	viewerId: string | null | undefined,
): boolean {
	if (!run || !viewerId || run.user_id !== viewerId) return false;
	if (!run.track_url) return false;
	if (!RECOMPUTABLE_SOURCES.includes(run.source)) return false;
	const metadata = run.metadata ?? {};
	if (metadata[METADATA_KEYS.distance_source] === 'pedometer') return false;
	if (metadata[METADATA_KEYS.distance_estimator] === CURRENT_DISTANCE_ESTIMATOR) return false;
	return true;
}

/// The recorder's original distance a recompute kept aside, or null when the
/// run was never recomputed (or the value is unusable).
export function recordedDistanceM(metadata: JsonObject | null | undefined): number | null {
	const raw = metadata?.[METADATA_KEYS.distance_recorded_m];
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
