/**
 * Pure geometry helpers for displaying a planned polyline. TS twin
 * of `apps/mobile_android/lib/route_geometry.dart` — kept in lockstep
 * so the route-detail scrubber renders identical positions on both
 * platforms. Add to the parity-pair list in CLAUDE.md if you grow
 * this module.
 */
import { lonDeltaDeg, wrapLonDeg } from './geo';
import { haversineMetres } from '../runs/run_stats';

export interface RouteWaypoint {
	lat: number;
	lng: number;
	elevation_m?: number | null;
}

/**
 * Interpolate the position along `waypoints` at the given normalized
 * `fraction` (0.0 = start, 1.0 = end). Returns null when the polyline
 * is too short to interpolate (`< 2` waypoints) or `fraction` is not
 * finite (NaN / ±Infinity) — clamping a non-finite fraction would
 * propagate NaN into the returned lat/lng.
 *
 * Distance-weighted — a long segment between two waypoints takes
 * proportionally more of the scrubber's range than a short segment,
 * so dragging at constant speed feels like dragging the runner at a
 * constant pace along the route.
 *
 * Used by the route-detail page's scrubber slider: the slider emits
 * a 0..1 value as the user drags from start to finish, this helper
 * produces the lat/lng to render the "runner" pulse on the map.
 */
export function interpolateAlongRoute(
	waypoints: RouteWaypoint[],
	fraction: number,
): RouteWaypoint | null {
	if (waypoints.length < 2) return null;
	if (!Number.isFinite(fraction)) return null;
	const f = Math.min(1, Math.max(0, fraction));
	const totalLen = cumulativeLengthM(waypoints);
	if (totalLen <= 0) {
		// Degenerate — all coincident. Snap to start.
		return waypoints[0];
	}
	const target = totalLen * f;
	let seen = 0;
	for (let i = 1; i < waypoints.length; i++) {
		const a = waypoints[i - 1];
		const b = waypoints[i];
		const segLen = haversineMetres(a.lat, a.lng, b.lat, b.lng);
		if (segLen <= 0) continue;
		const segEnd = seen + segLen;
		if (target <= segEnd || i === waypoints.length - 1) {
			const localT = Math.min(1, Math.max(0, (target - seen) / segLen));
			return {
				lat: a.lat + (b.lat - a.lat) * localT,
				lng: wrapLonDeg(a.lng + lonDeltaDeg(a.lng, b.lng) * localT),
				elevation_m: lerpNullable(
					a.elevation_m ?? null,
					b.elevation_m ?? null,
					localT,
				),
			};
		}
		seen = segEnd;
	}
	return waypoints[waypoints.length - 1];
}

/** How far past the expected position the matcher looks for the runner. */
const ROUTE_MATCH_LOOKAHEAD_M = 200;
/** How far behind the previous reading the matcher still accepts (GPS jitter). */
const ROUTE_MATCH_BACKTRACK_M = 50;
/**
 * A windowed match further off the line than this is not trusted: the matcher
 * looks for the runner further along instead. The off-route alert threshold.
 */
const ROUTE_MATCH_REACQUIRE_M = 40;
const ALONG_FWD_BIAS_PER_M = 0.05;
const ALONG_BACK_BIAS_PER_M = 0.5;
const MAX_ALONG_BIAS_M = 20;
// Uncapped, far below anything the geometry can notice (a 100 km gap buys
// 10 cm): settles a candidate pair the capped bias cannot separate — the two
// limbs of an out-and-back seen with no previous reading — towards the anchor.
const ALONG_CONTINUITY_PER_M = 1e-6;

export interface RouteProgress {
	/** Distance from the route start to the matched point, metres. */
	alongM: number;
	/** Distance from the runner to the nearest point anywhere on the line, metres. */
	offRouteM: number;
	/** Route length still to run from the matched point, metres. */
	remainingM: number;
}

/**
 * Where a runner FOLLOWING the route is along it, given where they were last.
 *
 * The inverse of `interpolateAlongRoute` for a live GPS fix, which is rarely
 * exactly on the planned line. The globally nearest point is the wrong answer
 * whenever the line passes the same place twice: on a loop the finish is as near as the start, so a run that has just
 * begun reads as finished; on an out-and-back the return leg lies on the
 * outbound one; a figure-eight crosses itself. This matcher only searches the
 * stretch of route the runner can plausibly be on — from
 * `ROUTE_MATCH_BACKTRACK_M` behind `prevAlongM` to `ROUTE_MATCH_LOOKAHEAD_M`
 * past `prevAlongM + travelledM` (the start of the route when there is no
 * previous reading) — and within it breaks a tie between overlapping legs in
 * favour of forward progress, with a bias capped at `MAX_ALONG_BIAS_M` so it
 * can never outweigh real distance off the line. When nothing in that window
 * is within `ROUTE_MATCH_REACQUIRE_M`, or the runner projects past its far
 * end, the rest of the route ahead is searched, so a runner who skips ahead or returns after a signal gap is
 * re-acquired; a runner still off the line keeps the windowed match, unless
 * there is no previous reading to keep, when the nearest point is taken.
 *
 * Each segment is projected in its own local planar frame, anchored at that
 * segment's start, but candidates are ranked by the great-circle distance to
 * the projected foot, the way `route_snap.ts` does it: a perpendicular
 * measured inside a segment's frame is scaled by that segment's own cos(lat),
 * so it is not comparable across segments.
 *
 * `offRouteM` is always the distance to the nearest point on the WHOLE line,
 * never to the matched stretch: a runner standing on the route is not off it,
 * whichever lap or leg the matcher has them on.
 *
 * Null when the polyline has `< 2` waypoints or the point is not finite. A
 * non-finite `prevAlongM` is no previous reading; a non-finite or negative
 * `travelledM` is zero.
 */
export function progressAlongRoute(
	point: { lat: number; lng: number },
	waypoints: RouteWaypoint[],
	prevAlongM: number | null,
	travelledM = 0,
): RouteProgress | null {
	if (waypoints.length < 2) return null;
	if (!Number.isFinite(point.lng) || !Number.isFinite(point.lat)) return null;
	const deg = Math.PI / 180;
	const rPerDeg = 6_371_000 * deg;

	const n = waypoints.length - 1;
	const segStart = new Array<number>(n);
	const segLen = new Array<number>(n);
	const tFree = new Array<number>(n);
	let total = 0;
	let offRouteM = Infinity;
	for (let i = 0; i < n; i++) {
		const a = waypoints[i];
		const b = waypoints[i + 1];
		segStart[i] = total;
		segLen[i] = haversineMetres(a.lat, a.lng, b.lat, b.lng);
		total += segLen[i];
		const cosLat = Math.cos(a.lat * deg);
		const bx = lonDeltaDeg(a.lng, b.lng) * cosLat * rPerDeg;
		const by = (b.lat - a.lat) * rPerDeg;
		const px = lonDeltaDeg(a.lng, point.lng) * cosLat * rPerDeg;
		const py = (point.lat - a.lat) * rPerDeg;
		const abLenSq = bx * bx + by * by;
		tFree[i] = abLenSq <= 0 ? 0 : Math.min(1, Math.max(0, (px * bx + py * by) / abLenSq));
		offRouteM = Math.min(offRouteM, offsetAt(i, tFree[i]));
	}
	if (!Number.isFinite(offRouteM) || !Number.isFinite(total)) return null;

	function offsetAt(i: number, t: number): number {
		const a = waypoints[i];
		const b = waypoints[i + 1];
		const footLat = a.lat + (b.lat - a.lat) * t;
		const footLng = wrapLonDeg(a.lng + lonDeltaDeg(a.lng, b.lng) * t);
		return haversineMetres(point.lat, point.lng, footLat, footLng);
	}

	const hasPrev = prevAlongM !== null && Number.isFinite(prevAlongM);
	const prev = hasPrev ? Math.min(total, Math.max(0, prevAlongM as number)) : 0;
	const travelled = Number.isFinite(travelledM) && travelledM > 0 ? travelledM : 0;
	const anchor = Math.min(total, prev + travelled);
	const lo = hasPrev ? Math.max(0, prev - ROUTE_MATCH_BACKTRACK_M) : 0;

	// Nearest point of the sub-line [fromM, toM], ranked by offset plus the
	// capped forward-progress bias around `anchor`. `pastEnd` marks a match
	// pinned to `toM` while the runner projects beyond it.
	type Match = { alongM: number; offsetM: number; pastEnd: boolean };
	function best(fromM: number, toM: number): Match | null {
		let found: Match | null = null;
		let bestCost = Infinity;
		for (let i = 0; i < n; i++) {
			const s = segStart[i];
			const len = segLen[i];
			if (s > toM || s + len < fromM) continue;
			const tLo = len > 0 ? Math.max(0, (fromM - s) / len) : 0;
			const tHi = len > 0 ? Math.min(1, (toM - s) / len) : 0;
			const t = Math.min(tHi, Math.max(tLo, tFree[i]));
			const offsetM = offsetAt(i, t);
			const alongM = s + t * len;
			const gap = alongM - anchor;
			const bias = Math.min(
				MAX_ALONG_BIAS_M,
				gap >= 0 ? gap * ALONG_FWD_BIAS_PER_M : -gap * ALONG_BACK_BIAS_PER_M,
			);
			const cost = offsetM + bias + Math.abs(gap) * ALONG_CONTINUITY_PER_M;
			if (cost < bestCost) {
				bestCost = cost;
				found = { alongM, offsetM, pastEnd: tFree[i] > t };
			}
		}
		return found;
	}

	let match = best(lo, anchor + ROUTE_MATCH_LOOKAHEAD_M);
	if (!match || match.offsetM > ROUTE_MATCH_REACQUIRE_M || match.pastEnd) {
		const ahead = best(lo, total);
		if (
			ahead &&
			(!match ||
				(ahead.offsetM < match.offsetM &&
					(!hasPrev || ahead.offsetM <= ROUTE_MATCH_REACQUIRE_M)))
		) {
			match = ahead;
		}
	}
	if (!match) return null;
	const alongM = Math.min(total, Math.max(0, match.alongM));
	return { alongM, offRouteM, remainingM: Math.max(0, total - alongM) };
}

/**
 * Total polyline length in metres via cumulative haversine. Cheap
 * O(n) — matches the recorder + run-stats helpers elsewhere in the
 * app.
 */
export function polylineLengthMetres(waypoints: RouteWaypoint[]): number {
	return cumulativeLengthM(waypoints);
}

/**
 * The point `distanceM` metres along the polyline — the "place this
 * course marker at mile 5" input path, an alternative to a map tap or a
 * typed lat/lng. `distanceM` is CLAMPED to [0, routeLength] so a value
 * past the finish snaps to the last waypoint rather than returning null.
 * Returns null only when there is no line to place on: `< 2` waypoints,
 * a zero-length (all-coincident) polyline, or a non-finite `distanceM`.
 *
 * Thin wrapper over polylineLengthMetres + the fraction-based
 * interpolateAlongRoute — fraction = clampedMetres / totalLength — so
 * the along-route position math stays in one place.
 */
export function markerPointAtDistance(
	waypoints: RouteWaypoint[],
	distanceM: number,
): RouteWaypoint | null {
	if (waypoints.length < 2) return null;
	if (!Number.isFinite(distanceM)) return null;
	const totalLen = polylineLengthMetres(waypoints);
	if (totalLen <= 0) return null;
	const clamped = Math.min(totalLen, Math.max(0, distanceM));
	return interpolateAlongRoute(waypoints, clamped / totalLen);
}

function cumulativeLengthM(waypoints: RouteWaypoint[]): number {
	let total = 0;
	for (let i = 1; i < waypoints.length; i++) {
		const a = waypoints[i - 1];
		const b = waypoints[i];
		total += haversineMetres(a.lat, a.lng, b.lat, b.lng);
	}
	return total;
}

function lerpNullable(
	a: number | null,
	b: number | null,
	t: number,
): number | null {
	if (a === null && b === null) return null;
	if (a === null) return b;
	if (b === null) return a;
	return a + (b - a) * t;
}
