/// Per-point keys a non-owner is never served. `distM` is the run's distance
/// credited up to and including a fix (docs/features/gps_distance.md
/// § Waypoint fields): on the first point after a trimmed start zone it states
/// how far the runner went inside the zone, and its gap to `distance_m` on the
/// last point states the same for an end zone. `clip_track_for_user` removes
/// it (20270829000021); this is the same rule applied to what the handler
/// returns, so a regression in either one alone does not reach a viewer.
/// A new per-point key that measures the run from its start belongs here and
/// in that function.
export const NON_OWNER_WITHHELD_POINT_KEYS = ['distM'] as const;

/// Whether a stored point is an off-track fix: one the recorder's distance
/// estimator took that failed its track gate (`offTrack: true`,
/// docs/features/gps_distance.md § Waypoint fields). It is distance input for
/// the server replay, never line, so no non-owner is served one.
/// `clip_track_for_user` drops them before its zone walk (20270829000032);
/// this drops them again from what the handler returns.
export function isOffTrackPoint(p: unknown): boolean {
  return (
    p !== null &&
    typeof p === 'object' &&
    !Array.isArray(p) &&
    (p as Record<string, unknown>).offTrack === true
  );
}

export function withholdFromNonOwner(points: unknown[]): unknown[] {
  return points.filter((p) => !isOffTrackPoint(p)).map((p) => {
    if (p === null || typeof p !== 'object' || Array.isArray(p)) return p;
    const out: Record<string, unknown> = { ...(p as Record<string, unknown>) };
    for (const key of NON_OWNER_WITHHELD_POINT_KEYS) delete out[key];
    return out;
  });
}
