// Which stored track fixes belong to the run's line. Since spec v1.4 a
// recorder stores every fix its distance estimator took and flags the ones
// that failed its track gate `offTrack: true` (a 30-50 m canopy fix on a
// watch; docs/features/gps_distance.md § Waypoint fields), so the server's
// distance replay sees them. They are distance input only: the map line, the
// elevation and climb, route matching, segments, the GPX export and the share
// card all read `onTrackPoints`. Splits and moving time keep every point,
// because they measure on `distM`, which every point carries. TS↔Dart parity
// pair with apps/mobile_android/lib/track_points.dart; keep in lockstep.

/**
 * Whether a stored track element is an off-track fix. Only the JSON boolean
 * `true` on an object marks one; an absent key (every track recorded before
 * the flag), `false` or any other value is on the line.
 */
export function isOffTrack(p: unknown): boolean {
	return (
		p !== null &&
		typeof p === 'object' &&
		!Array.isArray(p) &&
		(p as { offTrack?: unknown }).offTrack === true
	);
}

/** The track without its off-track fixes, in order; the input itself when it has none. */
export function onTrackPoints<T>(track: readonly T[]): T[] {
	return track.some(isOffTrack) ? track.filter((p) => !isOffTrack(p)) : (track as T[]);
}
