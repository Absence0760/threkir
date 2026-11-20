/**
 * What the park course maps draw beyond the line itself (issue #1352): the
 * distinct start areas of a park's courses, and whether a course finishes
 * where it starts, which decides whether its key shows one pin or two.
 * Web-only: the phone draws its own map key.
 */

import { mapPinnedLine } from '../routes/basemap_contrast.ts';
import { haversineMetres } from '../runs/run_stats.ts';
import { courseGate, gateBoxParts } from '../races/course_gates.ts';
import type { Gate } from '../geo/gate_crossing.ts';
import type { MessageKey } from '../i18n/messages.ts';

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

/** A catalogue segment's stored start and end line columns (decisions § 2402). */
export interface SegmentGateColumns {
	start_gate_lat: number | null;
	start_gate_lng: number | null;
	start_gate_bearing_deg: number | null;
	start_gate_half_width_m: number | null;
	end_gate_lat: number | null;
	end_gate_lng: number | null;
	end_gate_bearing_deg: number | null;
	end_gate_half_width_m: number | null;
}

/**
 * The lines a course page draws its start and finish boxes on (decisions
 * § 2582): the segment's stored lines, the ones the matcher times, read
 * through the race helper so a line means one thing everywhere. Null unless
 * both are whole: the page then shows its pins alone, as before.
 */
export function courseBoxGates(segment: SegmentGateColumns): { start: Gate; finish: Gate } | null {
	const row = {
		start_gate_lat: segment.start_gate_lat,
		start_gate_lng: segment.start_gate_lng,
		start_gate_bearing_deg: segment.start_gate_bearing_deg,
		start_gate_half_width_m: segment.start_gate_half_width_m,
		finish_gate_lat: segment.end_gate_lat,
		finish_gate_lng: segment.end_gate_lng,
		finish_gate_bearing_deg: segment.end_gate_bearing_deg,
		finish_gate_half_width_m: segment.end_gate_half_width_m,
	};
	const start = courseGate(row, 'start');
	const finish = courseGate(row, 'finish');
	if (!start || !finish) return null;
	const plain = (g: Gate): Gate => ({ lat: g.lat, lng: g.lng, bearingDeg: g.bearingDeg, halfWidthM: g.halfWidthM });
	return { start: plain(start), finish: plain(finish) };
}

/**
 * The one sentence a course page gives a runner (decisions § 2582): start
 * recording in the green box and follow the arrows to the red one (round the
 * loop n times on a lapped course). Where the start and finish share a spot,
 * a loop or an out-and-back, it is one start box, left and come back to, by
 * way of the Turn around mark when the course marks one.
 */
export function courseBoxInstruction(
	gates: { start: Gate; finish: Gate },
	hasTurn: boolean,
	laps: number | null | undefined,
): { key: MessageKey; params?: { n: number } } {
	const n = laps != null && laps > 0 ? laps : 1;
	if (gateBoxParts(gates.start, gates.finish).layout === 'shared') {
		return hasTurn ? { key: 'parks.boxesOutAndBack' } : { key: 'parks.boxesShared', params: { n } };
	}
	return { key: 'parks.boxesApart', params: { n } };
}

/** A lap longer than this many km (or miles) shows only every 5th badge at the whole-course zoom. */
export const OVERVIEW_BADGE_FULL_UNITS = 10;

/**
 * Whether the km or mile badge [label] shows at a course map's whole-course
 * zoom (decisions § 2582): every badge on a lap of up to
 * OVERVIEW_BADGE_FULL_UNITS, otherwise every 5th, so they never crowd the
 * line. The rest appear once the map is zoomed in.
 */
export function badgeAtOverview(label: number, lapUnits: number): boolean {
	return lapUnits <= OVERVIEW_BADGE_FULL_UNITS || label % 5 === 0;
}

/** A mark a course map's key can name. */
export type CourseKeyKind =
	| 'start'
	| 'finish'
	| 'startFinish'
	| 'startBox'
	| 'finishBox'
	| 'startFinishBox'
	| 'checkpoint'
	| 'turnaround'
	| 'distance'
	| 'direction';

/**
 * What a course map's key lists: only the marks the map draws at this moment
 * (decisions § 2582), so nobody hunts for one that is not there. The start
 * and finish are the boxes when the course has them, else the pins (one when
 * the line closes on itself); checkpoints and the turn-around when there are
 * any; the km / mile badges only while the map shows at least one, which the
 * map reports once a render settles; the direction arrows whenever there is
 * a line.
 */
export function courseKeyKinds(input: {
	boxes: 'none' | 'apart' | 'shared';
	finishesAtStart: boolean;
	checkpointMarkers: number;
	turnaround: boolean;
	badgesShown: boolean;
}): CourseKeyKind[] {
	const kinds: CourseKeyKind[] =
		input.boxes === 'shared'
			? ['startFinishBox']
			: input.boxes === 'apart'
				? ['startBox', 'finishBox']
				: input.finishesAtStart
					? ['startFinish']
					: ['start', 'finish'];
	if (input.checkpointMarkers > 0) kinds.push('checkpoint');
	if (input.turnaround) kinds.push('turnaround');
	if (input.badgesShown) kinds.push('distance');
	kinds.push('direction');
	return kinds;
}
