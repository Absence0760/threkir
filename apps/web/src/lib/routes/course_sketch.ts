// Pure geometry for CourseSketch, the consent-free drawing of a course that
// stands in for the map on a public share page until the visitor taps "Load
// map". Web only: the mobile share path links to this page, so there is no
// Dart twin (docs/architecture/parity_pairs.md).

import type { TrackPoint } from '../types';
import { unwrapLonDeg } from './geo';
import { toLinePoint } from '../runs/track_line';

/// The narrowest and widest box the sketch is drawn in. Narrower than this a
/// north-south course would push the page's signup ask off a phone's first
/// screen; wider and an east-west one becomes a sliver.
export const SKETCH_MIN_ASPECT = 1.1;
export const SKETCH_MAX_ASPECT = 2;

/// Width over height of the track's bounding box in equal-distance units
/// (longitude scaled by cos(midLat), as `projectTrack` draws it), or null
/// when there are fewer than two points or the box has no extent.
export function trackBoundsAspect(track: TrackPoint[]): number | null {
	if (!track || track.length < 2) return null;
	const points = track.map(toLinePoint);
	const refLng = points[0].lng;
	let minLat = points[0].lat;
	let maxLat = points[0].lat;
	let minLng = refLng;
	let maxLng = refLng;
	for (const p of points) {
		if (p.lat < minLat) minLat = p.lat;
		if (p.lat > maxLat) maxLat = p.lat;
		const lng = unwrapLonDeg(refLng, p.lng);
		if (lng < minLng) minLng = lng;
		if (lng > maxLng) maxLng = lng;
	}
	const midLat = (minLat + maxLat) / 2;
	const w = (maxLng - minLng) * Math.cos((midLat * Math.PI) / 180);
	const h = maxLat - minLat;
	if (!(w > 0) && !(h > 0)) return null;
	if (!(h > 0)) return Infinity;
	return w / h;
}

/// The aspect the sketch box takes: the route's own, clamped to
/// [SKETCH_MIN_ASPECT, SKETCH_MAX_ASPECT]. A route outside the band is
/// centred inside the box rather than cropped.
export function sketchAspect(track: TrackPoint[]): number {
	const a = trackBoundsAspect(track);
	if (a == null || !Number.isFinite(a)) return SKETCH_MAX_ASPECT;
	return Math.min(SKETCH_MAX_ASPECT, Math.max(SKETCH_MIN_ASPECT, a));
}

/// Whether the finish sits on the start at sketch scale, so the two markers
/// are drawn as one "Start / Finish" marker. `points` are projected viewBox
/// coordinates; `radius` is in the same units.
export function startMeetsFinish(points: { x: number; y: number }[], radius: number): boolean {
	if (points.length < 2) return true;
	const a = points[0];
	const b = points[points.length - 1];
	return Math.hypot(a.x - b.x, a.y - b.y) <= radius;
}
