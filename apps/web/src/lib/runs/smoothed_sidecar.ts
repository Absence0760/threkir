// The smoothed-position sidecar the job_worker writes beside a track it
// replayed, `{user_id}/{run_id}.smoothed.json.gz` in the `runs` bucket
// (docs/features/gps_distance.md § Waypoint fields). It holds the GPS
// distance smoother's position per stored waypoint plus the fingerprint of the
// exact track bytes it was computed from; a reader merges it only onto that
// track, and only onto a waypoint that carries no pair of its own, so a track
// re-uploaded after the sidecar was written keeps its own positions. The run
// names the track a stored sidecar was built for in
// `metadata.smoothed_sidecar_sha256`, and a reader fetches the sidecar only
// when that names the bytes it holds.
//
// Same rule as `_shared/smoothed_sidecar.ts` (Deno, clip-public-track) and
// `packages/api_client/lib/src/smoothed_sidecar.dart`; all three replay
// fixtures/smoothed_sidecar_vectors.json, as does the Go writer.

import { METADATA_KEYS } from '../core/schema';
import { hasSmoothedPosition, type LinePointSource } from './track_line';

export const SMOOTHED_SIDECAR_VERSION = 1;

export type TrackFingerprint = { points: number; sha256: string };

export function smoothedSidecarPath(userId: string, runId: string): string {
	return `${userId}/${runId}.smoothed.json.gz`;
}

/** Lower-case hex SHA-256 of the decompressed track bytes. */
export async function sha256Hex(bytes: Uint8Array): Promise<string> {
	const digest = await crypto.subtle.digest('SHA-256', bytes as Uint8Array<ArrayBuffer>);
	return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Whether the run's metadata names a sidecar built for the track whose bytes
 * hash to `sha256`: the worker records `smoothed_sidecar_sha256` while the
 * sidecar is stored, so a run without it, or whose hash names another track
 * (a re-upload), has nothing to fetch. Checked before the sidecar download so
 * a run with no sidecar costs no Storage request; the merge still checks the
 * sidecar's own fingerprint.
 */
export function sidecarNamedFor(metadata: unknown, sha256: string): boolean {
	if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) return false;
	return (metadata as Record<string, unknown>)[METADATA_KEYS.smoothed_sidecar_sha256] === sha256;
}

/** Whether a sidecar could add anything: a track with no smoothed pair on any waypoint. */
export function needsSmoothedSidecar(points: readonly LinePointSource[]): boolean {
	return points.length > 0 && !points.some(hasSmoothedPosition);
}

function usablePosition(v: unknown): v is [number, number] {
	if (!Array.isArray(v) || v.length !== 2) return false;
	const [lat, lng] = v;
	return (
		typeof lat === 'number' &&
		typeof lng === 'number' &&
		Number.isFinite(lat) &&
		Number.isFinite(lng) &&
		Math.abs(lat) <= 90 &&
		Math.abs(lng) <= 180
	);
}

/**
 * `points` with the sidecar's positions as `smoothedLat` / `smoothedLng`
 * where the waypoint has no pair of its own, or `points` itself when the
 * sidecar is not for this track (version, point count or hash differ) or is
 * not a sidecar at all. Never alters `lat` / `lng`.
 */
export function mergeSmoothedSidecar<T extends LinePointSource>(
	points: T[],
	sidecar: unknown,
	track: TrackFingerprint,
): T[] {
	if (!sidecar || typeof sidecar !== 'object' || Array.isArray(sidecar)) return points;
	const sc = sidecar as { version?: unknown; track?: unknown; positions?: unknown };
	const named = sc.track as { points?: unknown; sha256?: unknown } | null | undefined;
	if (
		sc.version !== SMOOTHED_SIDECAR_VERSION ||
		!named ||
		named.points !== track.points ||
		named.sha256 !== track.sha256 ||
		track.points !== points.length ||
		!Array.isArray(sc.positions) ||
		sc.positions.length !== points.length
	) {
		return points;
	}
	const positions = sc.positions;
	return points.map((p, i) => {
		const pos = positions[i];
		if (hasSmoothedPosition(p) || !usablePosition(pos)) return p;
		return { ...p, smoothedLat: pos[0], smoothedLng: pos[1] };
	});
}
