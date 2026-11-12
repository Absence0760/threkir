// The smoothed-position sidecar the job_worker writes beside a track it
// replayed, `{user_id}/{run_id}.smoothed.json.gz` in the `runs` bucket
// (docs/features/gps_distance.md § Waypoint fields): the GPS distance
// smoother's position per stored waypoint plus the fingerprint of the exact
// track bytes it was computed from. clip-public-track merges it before the
// privacy-zone clip, so `clip_track_for_user`'s either-pair-in-zone rule
// (20270719000005) sees every smoothed position a viewer will draw.
//
// The Deno copy of apps/web/src/lib/runs/smoothed_sidecar.ts; both replay
// fixtures/smoothed_sidecar_vectors.json, as do the Dart reader and the Go
// writer.

export const SMOOTHED_SIDECAR_VERSION = 1;

export type TrackFingerprint = { points: number; sha256: string };

type LinePoint = { smoothedLat?: unknown; smoothedLng?: unknown };

export function smoothedSidecarPath(userId: string, runId: string): string {
  return `${userId}/${runId}.smoothed.json.gz`;
}

/** Lower-case hex SHA-256 of the decompressed track bytes. */
export async function sha256Hex(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
}

function finite(v: unknown): v is number {
  return typeof v === 'number' && Number.isFinite(v);
}

function hasSmoothedPosition(p: unknown): boolean {
  if (!p || typeof p !== 'object') return false;
  const q = p as LinePoint;
  return finite(q.smoothedLat) && finite(q.smoothedLng);
}

/**
 * Whether the run's metadata names a sidecar built for the track whose bytes
 * hash to `sha256`: the job_worker records `smoothed_sidecar_sha256` while the
 * sidecar is stored, so a run without it, or whose hash names another track (a
 * re-upload), has nothing to fetch. Checked before the sidecar download so a
 * run with no sidecar costs no Storage request; the merge still checks the
 * sidecar's own fingerprint.
 */
export function sidecarNamedFor(metadata: unknown, sha256: string): boolean {
  if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) return false;
  return (metadata as Record<string, unknown>).smoothed_sidecar_sha256 === sha256;
}

/** Whether a sidecar could add anything: a track with no smoothed pair on any waypoint. */
export function needsSmoothedSidecar(points: readonly unknown[]): boolean {
  return points.length > 0 && !points.some(hasSmoothedPosition);
}

function usablePosition(v: unknown): v is [number, number] {
  if (!Array.isArray(v) || v.length !== 2) return false;
  const [lat, lng] = v;
  return finite(lat) && finite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
}

/**
 * `points` with the sidecar's positions as `smoothedLat` / `smoothedLng`
 * where the waypoint is an object with no pair of its own, or `points`
 * itself when the sidecar is not for this track (version, point count or
 * hash differ) or is not a sidecar at all. Never alters `lat` / `lng`.
 */
export function mergeSmoothedSidecar<T>(
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
  const positions = sc.positions as unknown[];
  return points.map((p, i) => {
    const pos = positions[i];
    if (!p || typeof p !== 'object' || Array.isArray(p)) return p;
    if (hasSmoothedPosition(p) || !usablePosition(pos)) return p;
    return { ...(p as Record<string, unknown>), smoothedLat: pos[0], smoothedLng: pos[1] } as T;
  });
}
