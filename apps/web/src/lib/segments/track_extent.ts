/**
 * The lat/lng extent of a run track, for the catalogue candidate lookup
 * (`global_segments_in_bbox`, decisions § 2392). One implementation for both
 * callers: the web fallback scorer imports it, and the `segment-match` Edge
 * Function runs it from the generated matcher bundle.
 *
 * Measured over LINE positions (`runs/track_line.ts`), the positions the
 * matcher itself measures, so a smoothed fix is never outside the box the
 * candidates were chosen by. A track whose longitudes span more than half the
 * globe is taken to cross the antimeridian and widened to every longitude:
 * that over-admits candidates, which the matcher then rejects, and never
 * under-admits one. Null for an empty track or a non-finite position.
 */

import { lineLat, lineLng, type LinePointSource } from '../runs/track_line';

export interface TrackExtent {
	minLat: number;
	minLng: number;
	maxLat: number;
	maxLng: number;
}

export function trackExtent(points: readonly LinePointSource[]): TrackExtent | null {
	if (points.length === 0) return null;
	let minLat = Infinity;
	let maxLat = -Infinity;
	let minLng = Infinity;
	let maxLng = -Infinity;
	for (const p of points) {
		const lat = lineLat(p);
		const lng = lineLng(p);
		if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
		if (lat < minLat) minLat = lat;
		if (lat > maxLat) maxLat = lat;
		if (lng < minLng) minLng = lng;
		if (lng > maxLng) maxLng = lng;
	}
	const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);
	minLat = clamp(minLat, -90, 90);
	maxLat = clamp(maxLat, -90, 90);
	minLng = clamp(minLng, -180, 180);
	maxLng = clamp(maxLng, -180, 180);
	if (maxLng - minLng > 180) {
		minLng = -180;
		maxLng = 180;
	}
	return { minLat, minLng, maxLat, maxLng };
}
