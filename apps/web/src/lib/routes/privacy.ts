// Privacy zones — geofences clipped from the start and end of any
// track rendered on a public surface. Decisions §33 covers the why
// and the known v1 gaps (notably routes.start_point, which is set
// server-side by trigger and is unaware of the owner's zones).
//
// Pure functions. Unit-testable. No Svelte / Supabase dependencies.

import { haversineMetres } from '../runs/run_stats';
import { hasSmoothedPosition, type LinePointSource } from '../runs/track_line';

/// Declared as an ALIAS, not an interface, and that is load-bearing rather
/// than stylistic: TypeScript gives an object type an implicit index signature
/// only when it is an alias — an interface stays open to declaration merging
/// and so never gets one — and without one a zone list cannot be assigned to
/// the `Json` of the `user_settings.prefs` bag it is persisted into (§ 1363).
/// An interface here does not fail the write; it pushes every writer into
/// restating the fields by hand, which is a second declaration of the privacy
/// contract § 33 makes.
export type PrivacyZone = {
	lat: number;
	lng: number;
	radius_m: number;
};

export type LatLng = {
	lat: number;
	lng: number;
};

export const PRIVACY_ZONES_KEY = 'privacy_zones';

/// Returns true when `point` is within any of `zones` by haversine
/// distance. Empty zone list -> always false.
export function isInAnyZone(point: LatLng, zones: PrivacyZone[]): boolean {
	for (const z of zones) {
		if (haversineMetres(point.lat, point.lng, z.lat, z.lng) <= z.radius_m) return true;
	}
	return false;
}

/// True when either position a stored fix carries is inside a zone: the raw
/// `lat` / `lng`, or the GPS smoother's `smoothedLat` / `smoothedLng` when both
/// halves are finite. The run line draws the smoothed position, and the
/// smoother can pull a fix just outside the edge to just inside it, so a raw
/// test alone would let a drawn endpoint sit in the zone. Mirrors the
/// end-walk predicate of `clip_track_for_user`
/// (migration 20270719000005).
export function isFixInAnyZone(point: LinePointSource, zones: PrivacyZone[]): boolean {
	if (isInAnyZone(point, zones)) return true;
	return (
		hasSmoothedPosition(point) &&
		isInAnyZone({ lat: point.smoothedLat as number, lng: point.smoothedLng as number }, zones)
	);
}

/// Walk forward from index 0 and drop fixes in any zone; walk
/// backward from the end with the same predicate; keep the
/// contiguous middle. A fix is in a zone when its raw OR its
/// smoothed position is (`isFixInAnyZone`), the rule the server's
/// `clip_track_for_user` applies for non-owners, so an image the
/// owner exports carries the same trimmed line a stranger is served.
/// We deliberately don't slice out *interior* in-zone segments
/// (e.g. a loop that returns home mid-run and leaves again) because
/// (a) the leak we're protecting is "where you live," not "where
/// you've ever been," and (b) gapping the polyline mid-track looks
/// broken.
///
/// When the result would be empty (every point is in a zone), we
/// return an empty array — callers should render no polyline at all
/// rather than a single point that gives the location away.
export function clipPointsToZones<T extends LinePointSource>(points: T[], zones: PrivacyZone[]): T[] {
	if (zones.length === 0 || points.length === 0) return points;

	let start = 0;
	while (start < points.length && isFixInAnyZone(points[start], zones)) start++;
	if (start >= points.length) return [];

	let end = points.length - 1;
	while (end > start && isFixInAnyZone(points[end], zones)) end--;

	return points.slice(start, end + 1);
}
