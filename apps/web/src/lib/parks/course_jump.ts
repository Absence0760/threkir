/**
 * The "jump to" buttons over a park course map: which ones a course gets and
 * where each one takes the map. Start and Finish on a point-to-point, one
 * Start and finish where they share a spot (as the map draws one box there,
 * decisions § 2582), and Whole course always. Pure.
 *
 * Parity pair with apps/mobile_android/lib/course_jump.dart. Both read
 * fixtures/course_jump_cases.json.
 */

import type { Gate } from '../geo/gate_crossing.ts';
import { fromPlane, gateBoxParts, planeXY, type GatePoint } from '../races/course_gates.ts';

/** A jump to a start or finish shows at least this much ground across, so it is never absurdly close. */
export const COURSE_JUMP_MIN_SPAN_M = 120;

/** The closest a jump zooms, whatever the box. */
export const COURSE_JUMP_MAX_ZOOM = 18;

export type CourseJumpTarget = 'start' | 'finish' | 'startFinish' | 'course';

export interface JumpBounds {
	south: number;
	west: number;
	north: number;
	east: number;
}

export interface CourseJump {
	target: CourseJumpTarget;
	bounds: JumpBounds;
}

function finitePoint(p: GatePoint): boolean {
	return Number.isFinite(p.lat) && Number.isFinite(p.lng);
}

function boundsOf(points: readonly GatePoint[]): JumpBounds {
	let south = Infinity;
	let west = Infinity;
	let north = -Infinity;
	let east = -Infinity;
	for (const p of points) {
		south = Math.min(south, p.lat);
		north = Math.max(north, p.lat);
		west = Math.min(west, p.lng);
		east = Math.max(east, p.lng);
	}
	return { south, west, north, east };
}

/** The bounds of [points], widened about their centre to at least COURSE_JUMP_MIN_SPAN_M each way. */
function closeBounds(points: readonly GatePoint[]): JumpBounds {
	const b = boundsOf(points);
	const centre = { lat: (b.south + b.north) / 2, lng: (b.west + b.east) / 2 };
	const corner = planeXY(centre, { lat: b.north, lng: b.east });
	const hx = Math.max(Math.abs(corner.x), COURSE_JUMP_MIN_SPAN_M / 2);
	const hy = Math.max(Math.abs(corner.y), COURSE_JUMP_MIN_SPAN_M / 2);
	const sw = fromPlane(centre, -hx, -hy);
	const ne = fromPlane(centre, hx, hy);
	return { south: sw.lat, west: sw.lng, north: ne.lat, east: ne.lng };
}

/**
 * The buttons a course map shows, in order. With [gates] each jump fits its
 * box (the one box a shared start and finish make); without, the line's
 * first and last points, one jump when [endsShared] says the map draws one
 * pin for both. Empty for a line the map does not draw.
 */
export function courseJumps(input: {
	gates: { start: Gate; finish: Gate } | null;
	line: readonly GatePoint[];
	endsShared: boolean;
}): CourseJump[] {
	const line = input.line.filter(finitePoint);
	if (line.length < 2) return [];
	const out: CourseJump[] = [];
	if (input.gates) {
		for (const part of gateBoxParts(input.gates.start, input.gates.finish).parts) {
			const target: CourseJumpTarget = part.which === 'both' ? 'startFinish' : part.which;
			out.push({ target, bounds: closeBounds([...part.box, ...part.line]) });
		}
	} else if (input.endsShared) {
		out.push({ target: 'startFinish', bounds: closeBounds([line[0]]) });
	} else {
		out.push({ target: 'start', bounds: closeBounds([line[0]]) });
		out.push({ target: 'finish', bounds: closeBounds([line[line.length - 1]]) });
	}
	out.push({ target: 'course', bounds: boundsOf(line) });
	return out;
}
