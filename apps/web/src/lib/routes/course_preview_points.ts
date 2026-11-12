import type { TrackPoint } from '../types';
import { buildFlyoverPath, type PathPoint } from './flyover_path';
import { progressAlongRoute } from './route_geometry';
import { runAltitude } from '../runs/run_altitude';
import { lineLat, lineLng } from '../runs/track_line';

/**
 * The 3D course preview's input from each page that offers it: a route's
 * waypoints, a run's track and a route's climb markers, read into the
 * `PathPoint` shape the flyover consumes. Pure, so the three entry points
 * agree on what a usable point is.
 */

/** A climb marker further than this from the line it names is left unnamed. */
export const CLIMB_MARKER_MAX_OFFSET_M = 100;

/** The fewest points a line needs before there is a course to fly. */
export const MIN_PREVIEW_POINTS = 2;

/**
 * Whether the points make a course the preview can fly: at least two distinct
 * positions, so the path has a length for the camera to follow. The entry
 * points hide their button otherwise, since the flyover has nothing to show.
 */
export function hasPreviewableCourse(points: readonly PathPoint[]): boolean {
	return points.length >= MIN_PREVIEW_POINTS && buildFlyoverPath(points).totalM > 0;
}

function finite(v: unknown): v is number {
	return typeof v === 'number' && Number.isFinite(v);
}

/**
 * A route's waypoints as path points. The caller passes the waypoints it
 * already renders, which `fetchRouteById` has privacy-clipped for a
 * non-owner, so the preview can show no more than the 2D map does.
 */
export function routePathPoints(
	waypoints: readonly { lat?: unknown; lng?: unknown; ele?: unknown }[] | null | undefined,
): PathPoint[] {
	const out: PathPoint[] = [];
	for (const w of waypoints ?? []) {
		if (!w || !finite(w.lat) || !finite(w.lng)) continue;
		out.push({ lat: w.lat, lng: w.lng, ele: finite(w.ele) ? w.ele : null });
	}
	return out;
}

/**
 * A recorded track as path points: the drawn line (smoothed position where
 * the fix carries one, off-track fixes dropped) with the altitude series the
 * run's own elevation profile reads (`runAltitude`), so the replay climbs the
 * same hills the chart shows. `noiseBandM` is that series' noise band, which
 * the climb detector widens its close on. A non-owner's track must already be
 * the `clip-public-track` output.
 */
export function trackPreview(
	track: readonly TrackPoint[] | null | undefined,
	source?: string | null,
): { points: PathPoint[]; noiseBandM: number | undefined } {
	if (!track || track.length === 0) return { points: [], noiseBandM: undefined };
	const altitude = runAltitude(track as TrackPoint[], source);
	const points: PathPoint[] = [];
	for (const p of altitude.track) {
		const lat = lineLat(p);
		const lng = lineLng(p);
		if (!finite(lat) || !finite(lng)) continue;
		points.push({ lat, lng, ele: finite(p.ele) ? p.ele : null });
	}
	return { points, noiseBandM: altitude.minDeltaM };
}

/**
 * Names for the preview's climbs, from the route's `climb` markers. Each is
 * placed by projecting the marker onto the line the preview flies rather than
 * by its stored `position_m`, which is measured along the unclipped route and
 * would land in the wrong place on a non-owner's clipped line. A marker off
 * that line (inside a clipped-away stretch, or dropped beside the course) is
 * left out.
 */
export function climbNamesFromMarkers(
	markers: readonly { kind: string; label: string | null; lat: number; lng: number }[],
	points: readonly PathPoint[],
): { dM: number; name: string }[] {
	if (points.length < MIN_PREVIEW_POINTS) return [];
	const line = points.map((p) => ({ lat: p.lat, lng: p.lng }));
	const out: { dM: number; name: string }[] = [];
	for (const mk of markers) {
		if (mk.kind !== 'climb') continue;
		const name = mk.label?.trim();
		if (!name) continue;
		const at = progressAlongRoute({ lat: mk.lat, lng: mk.lng }, line, null);
		if (!at || at.offRouteM > CLIMB_MARKER_MAX_OFFSET_M) continue;
		out.push({ dM: at.alongM, name });
	}
	return out.sort((a, b) => a.dM - b.dM);
}
