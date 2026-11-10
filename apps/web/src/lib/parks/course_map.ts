/**
 * What the park course maps draw beyond the line itself (issue #1352): the
 * distinct start areas of a park's courses, and whether a course finishes
 * where it starts, which decides whether its key shows one pin or two.
 * Web-only: the phone draws its own map key.
 */

import { mapPinnedLine } from '../routes/basemap_contrast.ts';
import { haversineMetres } from '../runs/run_stats.ts';

export interface LatLng {
	lat: number;
	lng: number;
}

/** Starts closer than this read as one start area. */
export const SHARED_START_M = 75;

/** A finish this close to the start draws on top of it. */
export const SAME_PLACE_M = 30;

/**
 * The start of every course with a line, merging starts within
 * [SHARED_START_M] of one already kept, in input order.
 */
export function distinctStarts(lines: readonly (readonly LatLng[])[]): LatLng[] {
	const out: LatLng[] = [];
	for (const line of lines) {
		const s = line[0];
		if (!s || !Number.isFinite(s.lat) || !Number.isFinite(s.lng)) continue;
		if (out.some((o) => haversineMetres(o.lat, o.lng, s.lat, s.lng) < SHARED_START_M)) continue;
		out.push({ lat: s.lat, lng: s.lng });
	}
	return out;
}

/** Whether a line ends within [SAME_PLACE_M] of where it starts. */
export function finishesAtStart(line: readonly LatLng[]): boolean {
	if (line.length < 2) return false;
	const a = line[0];
	const b = line[line.length - 1];
	return haversineMetres(a.lat, a.lng, b.lat, b.lng) < SAME_PLACE_M;
}

/**
 * The fill of a checkpoint pin: the violet rung, apart from the coral line,
 * the green start, the red finish and the amber highlight. The pin's ring
 * (`mapOverlayOutline`) is what clears 3:1 against the ground.
 */
export const checkpointPinColour = mapPinnedLine;
