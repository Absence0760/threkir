// Course start and finish lines (#1305, timing lines phase 2, decisions
// § 2390): reading a course's lines off its row, the geometry the editor and
// the maps draw, the editor's inline warnings, and the Arm preflight. Pure.
//
// Parity pair with apps/mobile_android/lib/course_gates.dart. Both read
// fixtures/course_gates_cases.json, so a rule changes there or nowhere.

import type { GateSource } from '../types';
import { GATE_EARTH_RADIUS_M, GATE_HALF_WIDTH_RACE_M, type Gate } from '../geo/gate_crossing';

/** Mirrors the event_courses half-width CHECK (5-100 m). */
export const COURSE_GATE_HALF_WIDTH_MIN_M = 5;
export const COURSE_GATE_HALF_WIDTH_MAX_M = 100;
/** The width a derived line and a newly placed one get (§ 2377). */
export const COURSE_GATE_DEFAULT_HALF_WIDTH_M = GATE_HALF_WIDTH_RACE_M;
/** A line further than this from the course route is probably misplaced. */
export const COURSE_GATE_ROUTE_WARN_M = 100;
/** A line facing more than this away from the route's direction faces against it. */
export const COURSE_GATE_AGAINST_ROUTE_DEG = 90;

export type GateWhich = 'start' | 'finish';

export interface CourseGate extends Gate {
	source: GateSource;
}

export interface GatePoint {
	lat: number;
	lng: number;
}

/** The line columns of an event_courses or race_session_courses row. */
export interface CourseGateColumns {
	start_gate_lat: number | null;
	start_gate_lng: number | null;
	start_gate_bearing_deg: number | null;
	start_gate_half_width_m: number | null;
	start_gate_source?: string | null;
	finish_gate_lat: number | null;
	finish_gate_lng: number | null;
	finish_gate_bearing_deg: number | null;
	finish_gate_half_width_m: number | null;
	finish_gate_source?: string | null;
}

function finite(v: unknown): v is number {
	return typeof v === 'number' && Number.isFinite(v);
}

/**
 * One line of a row, or null when the row has none. A frozen copy carries no
 * source, so it reads as `derived`; nothing that reads a frozen copy edits it.
 */
export function courseGate(row: CourseGateColumns, which: GateWhich): CourseGate | null {
	const lat = which === 'start' ? row.start_gate_lat : row.finish_gate_lat;
	const lng = which === 'start' ? row.start_gate_lng : row.finish_gate_lng;
	const bearingDeg = which === 'start' ? row.start_gate_bearing_deg : row.finish_gate_bearing_deg;
	const halfWidthM = which === 'start' ? row.start_gate_half_width_m : row.finish_gate_half_width_m;
	const source = which === 'start' ? row.start_gate_source : row.finish_gate_source;
	if (!finite(lat) || !finite(lng) || !finite(bearingDeg) || !finite(halfWidthM)) return null;
	return {
		lat,
		lng,
		bearingDeg,
		halfWidthM,
		source: source === 'organiser' ? 'organiser' : 'derived'
	};
}

/** Any finite bearing into [0, 360). */
export function normalizeBearing(deg: number): number {
	const b = ((deg % 360) + 360) % 360;
	return b >= 360 ? 0 : b;
}

/** A half-width held to the CHECK's range, rounded to the metre. */
export function clampHalfWidth(m: number): number {
	if (!Number.isFinite(m)) return COURSE_GATE_DEFAULT_HALF_WIDTH_M;
	return Math.min(COURSE_GATE_HALF_WIDTH_MAX_M, Math.max(COURSE_GATE_HALF_WIDTH_MIN_M, Math.round(m)));
}

function rad(deg: number): number {
	return (deg * Math.PI) / 180;
}

function deg(r: number): number {
	return (r * 180) / Math.PI;
}

function wrapLng(d: number): number {
	if (d >= 180) return d - 360;
	if (d < -180) return d + 360;
	return d;
}

/** (lat, lng) on the tangent plane at origin, metres east (x) and north (y). */
export function planeXY(origin: GatePoint, p: GatePoint): { x: number; y: number } {
	return {
		x: rad(wrapLng(p.lng - origin.lng)) * GATE_EARTH_RADIUS_M * Math.cos(rad(origin.lat)),
		y: rad(p.lat - origin.lat) * GATE_EARTH_RADIUS_M
	};
}

/** The inverse of planeXY. */
export function fromPlane(origin: GatePoint, x: number, y: number): GatePoint {
	return {
		lat: origin.lat + deg(y / GATE_EARTH_RADIUS_M),
		lng: wrapLng(origin.lng + deg(x / (GATE_EARTH_RADIUS_M * Math.cos(rad(origin.lat)))))
	};
}

/** Degrees clockwise from north, from `from` toward `to`, in [0, 360). */
export function bearingTo(from: GatePoint, to: GatePoint): number {
	const { x, y } = planeXY(from, to);
	return normalizeBearing(deg(Math.atan2(x, y)));
}

/** The point `distM` from `origin` along `bearingDeg`. */
export function offsetPoint(origin: GatePoint, bearingDeg: number, distM: number): GatePoint {
	return fromPlane(origin, distM * Math.sin(rad(bearingDeg)), distM * Math.cos(rad(bearingDeg)));
}

/** The line's two ends, left of travel first, as gate_crossing measures it. */
export function gateLineEnds(gate: Gate): [GatePoint, GatePoint] {
	const b = rad(gate.bearingDeg);
	const ex = gate.halfWidthM * Math.cos(b);
	const ey = -gate.halfWidthM * Math.sin(b);
	return [fromPlane(gate, -ex, -ey), fromPlane(gate, ex, ey)];
}

/** Where the direction arrow ends: ahead of the centre by the half-width, at least 20 m. */
export function gateArrowTip(gate: Gate): GatePoint {
	return offsetPoint(gate, gate.bearingDeg, Math.max(20, gate.halfWidthM));
}

/** How deep a drawn start or finish box is, from its line. */
export const COURSE_GATE_BOX_DEPTH_M = 10;
/** Start and finish lines whose centres sit this close, facing the same way or opposite ways, sit at one spot. */
export const COURSE_GATE_SHARED_SPOT_M = 10;
/** How far from parallel (or from opposed) two lines may face and still share a spot. */
export const COURSE_GATE_SHARED_SPOT_DEG = 20;

/** The point on the line at `f` of its half-width: -1 its left end, 0 the centre, 1 its right end. */
export function gatePointAlong(gate: Gate, f: number): GatePoint {
	const b = rad(gate.bearingDeg);
	return fromPlane(gate, f * gate.halfWidthM * Math.cos(b), -f * gate.halfWidthM * Math.sin(b));
}

/**
 * Which side of its line a box sits: behind it (where a runner waits to
 * start), ahead (where one stops), or centred on it (a start and finish at
 * one spot, half behind and half ahead).
 */
export type GateBoxSide = 'behind' | 'ahead' | 'centred';

/**
 * The box on one side of a line, `depthM` deep, from `from` to `to` along the
 * line (as gatePointAlong). Corners: the near edge first, its left end then
 * its right (left of travel), then the far right and far left corners. For
 * `behind` and `ahead` the near edge is on the line, and leaving a `behind`
 * box through it, or entering an `ahead` one, is crossing the line. A
 * `centred` box runs from `depthM / 2` behind the line to `depthM / 2` ahead,
 * its near edge the one behind, so the line crosses its middle.
 */
export function gateBox(gate: Gate, depthM: number, side: GateBoxSide, from = -1, to = 1): GatePoint[] {
	const b = rad(gate.bearingDeg);
	const ax = gate.halfWidthM * Math.cos(b);
	const ay = -gate.halfWidthM * Math.sin(b);
	const [near, far] = side === 'ahead' ? [0, depthM] : side === 'behind' ? [0, -depthM] : [-depthM / 2, depthM / 2];
	const at = (f: number, k: number) => fromPlane(gate, f * ax + k * Math.sin(b), f * ay + k * Math.cos(b));
	return [at(from, near), at(to, near), at(to, far), at(from, far)];
}

/** Whether a start line and a finish line sit at one spot: an out-and-back's or a loop's. */
export function gatesShareSpot(start: Gate, finish: Gate): boolean {
	const { x, y } = planeXY(start, finish);
	if (Math.sqrt(x * x + y * y) > COURSE_GATE_SHARED_SPOT_M) return false;
	const d = bearingDelta(start.bearingDeg, finish.bearingDeg);
	return d <= COURSE_GATE_SHARED_SPOT_DEG || d >= 180 - COURSE_GATE_SHARED_SPOT_DEG;
}

/** One box on a course map. */
export interface GateBoxPart {
	/** The line it belongs to, or 'both' for the one box a start and finish at one spot share. */
	which: GateWhich | 'both';
	/** As gateBox gives it: behind the start line, ahead of the finish line, centred on a shared one. */
	box: GatePoint[];
	/** The timing line across the box: the stretch of the stored line it covers. */
	line: [GatePoint, GatePoint];
}

/**
 * How a course's start and finish boxes lie:
 * - `apart`: two boxes in two places, the start box behind its line and the
 *   finish box ahead of its own.
 * - `shared`: the lines sit at one spot (a loop, or an out-and-back), so it
 *   is one box in one colour, centred on the start line, which crosses its
 *   middle. Never two colours at one spot: a runner would read half of it as
 *   the start and half as the finish (decisions § 2582).
 */
export type GateBoxLayout = 'apart' | 'shared';

/**
 * Where a box's flag and name go: the middle of the box's far side, so at a
 * close zoom it sits beside the box rather than over the line. One for a box
 * the start and finish share.
 */
export interface GateBoxMarker {
	which: GateWhich | 'both';
	at: GatePoint;
}

/** The start and finish boxes a course map draws (decisions § 2582). */
export function gateBoxParts(
	start: Gate | null,
	finish: Gate | null,
	depthM: number = COURSE_GATE_BOX_DEPTH_M,
): { layout: GateBoxLayout; parts: GateBoxPart[]; markers: GateBoxMarker[] } {
	const part = (which: GateWhich | 'both', gate: Gate): GateBoxPart => ({
		which,
		box: gateBox(gate, depthM, which === 'both' ? 'centred' : which === 'start' ? 'behind' : 'ahead'),
		line: gateLineEnds(gate),
	});
	const marker = (which: GateWhich | 'both', gate: Gate, away: number, distM: number): GateBoxMarker => ({
		which,
		at: offsetPoint(gate, away, distM),
	});
	const back = (g: Gate) => g.bearingDeg + 180;
	if (start && finish && gatesShareSpot(start, finish)) {
		return {
			layout: 'shared',
			parts: [part('both', start)],
			markers: [marker('both', start, back(start), depthM / 2)],
		};
	}
	const parts: GateBoxPart[] = [];
	const markers: GateBoxMarker[] = [];
	if (start) {
		parts.push(part('start', start));
		markers.push(marker('start', start, back(start), depthM));
	}
	if (finish) {
		parts.push(part('finish', finish));
		markers.push(marker('finish', finish, finish.bearingDeg, depthM));
	}
	return { layout: 'apart', parts, markers };
}

/**
 * The edges a course is timed by, read off the boxes gateBoxParts draws
 * (decisions § 2589): leaving the start box forward is a forward crossing of
 * `startExit`, with the box behind it; entering the finish box is a forward
 * crossing of `finishEntry`, with the box `depthM` ahead of it. Apart, they are
 * the start and finish lines themselves. At a shared spot, the exit is the
 * box's far edge and the entry is its near edge on a loop, or its far edge
 * facing back on an out-and-back, so the timed stretch is `depthM` shorter
 * than line to line.
 */
export interface GateTimingEdges {
	layout: GateBoxLayout;
	startExit: Gate;
	finishEntry: Gate;
	depthM: number;
}

/** A line along a drawn box edge from corner `a` to corner `b`, facing `bearingDeg`. */
function edgeGate(a: GatePoint, b: GatePoint, bearingDeg: number, halfWidthM: number): Gate {
	const { x, y } = planeXY(a, b);
	const mid = fromPlane(a, x / 2, y / 2);
	return { lat: mid.lat, lng: mid.lng, bearingDeg: normalizeBearing(bearingDeg), halfWidthM };
}

/** The timing edges of a course with both lines (decisions § 2589). */
export function gateTimingEdges(start: Gate, finish: Gate, depthM: number = COURSE_GATE_BOX_DEPTH_M): GateTimingEdges {
	const { layout, parts } = gateBoxParts(start, finish, depthM);
	if (layout === 'shared') {
		const [nearL, nearR, farR, farL] = parts[0].box;
		const sameWay = bearingDelta(start.bearingDeg, finish.bearingDeg) <= 90;
		return {
			layout,
			startExit: edgeGate(farL, farR, start.bearingDeg, start.halfWidthM),
			finishEntry: sameWay
				? edgeGate(nearL, nearR, start.bearingDeg, start.halfWidthM)
				: edgeGate(farR, farL, start.bearingDeg + 180, start.halfWidthM),
			depthM,
		};
	}
	const [s, f] = parts;
	return {
		layout,
		startExit: edgeGate(s.box[0], s.box[1], start.bearingDeg, start.halfWidthM),
		finishEntry: edgeGate(f.box[0], f.box[1], finish.bearingDeg, finish.halfWidthM),
		depthM,
	};
}

export interface GateRouteRelation {
	/** Distance from the line's centre to the nearest point of the route. */
	distanceM: number;
	/** The route's direction of travel at that point. */
	routeBearingDeg: number;
	/** The line faces more than COURSE_GATE_AGAINST_ROUTE_DEG away from the route. */
	against: boolean;
}

/** Smallest angle between two bearings, 0..180. */
export function bearingDelta(a: number, b: number): number {
	const d = Math.abs(normalizeBearing(a) - normalizeBearing(b));
	return d > 180 ? 360 - d : d;
}

/**
 * How a line sits against a route, on the tangent plane at the line's centre.
 * Null for a route with fewer than two distinct points.
 */
export function gateRouteRelation(gate: Gate, route: readonly GatePoint[]): GateRouteRelation | null {
	let best: { d: number; bearing: number } | null = null;
	let prev: { x: number; y: number } | null = null;
	for (const p of route) {
		if (!finite(p.lat) || !finite(p.lng)) continue;
		const cur = planeXY(gate, p);
		if (prev !== null) {
			const dx = cur.x - prev.x;
			const dy = cur.y - prev.y;
			const len2 = dx * dx + dy * dy;
			if (len2 > 0) {
				const t = Math.max(0, Math.min(1, -(prev.x * dx + prev.y * dy) / len2));
				const px = prev.x + t * dx;
				const py = prev.y + t * dy;
				const d = Math.sqrt(px * px + py * py);
				if (best === null || d < best.d) {
					best = { d, bearing: normalizeBearing(deg(Math.atan2(dx, dy))) };
				}
			}
		}
		prev = cur;
	}
	if (best === null) return null;
	return {
		distanceM: best.d,
		routeBearingDeg: best.bearing,
		against: bearingDelta(gate.bearingDeg, best.bearing) > COURSE_GATE_AGAINST_ROUTE_DEG
	};
}

/** How a race session starts its clock (#1306): the values of `events.race_start_mode` and `race_sessions.start_mode`. */
export type SessionStartMode = 'host_go' | 'scheduled' | 'self_timed';

export type CourseGateWarning = 'far_from_route' | 'against_route' | 'self_cross' | 'start_required';

/**
 * The editor's inline warnings for one line. `route` is what the organiser
 * can see of the course route, or null when the course has none.
 */
export function gateWarnings(input: {
	which: GateWhich;
	gate: Gate | null;
	route: readonly GatePoint[] | null;
	selfCross: boolean;
	mode: SessionStartMode;
}): CourseGateWarning[] {
	const out: CourseGateWarning[] = [];
	if (input.gate === null) {
		if (input.which === 'start' && input.mode === 'self_timed') out.push('start_required');
		return out;
	}
	const rel = input.route ? gateRouteRelation(input.gate, input.route) : null;
	if (rel !== null) {
		if (rel.distanceM > COURSE_GATE_ROUTE_WARN_M) out.push('far_from_route');
		else if (rel.against) out.push('against_route');
	}
	if (input.which === 'finish' && input.selfCross) out.push('self_cross');
	return out;
}

/** One course as the Arm preflight sees it. */
export interface PreflightCourse {
	id: string;
	startGate: CourseGate | null;
	finishGate: CourseGate | null;
	hasFinishPoint: boolean;
	selfCross: boolean;
	/** The course route as the organiser can see it, or null when unknown. */
	route: readonly GatePoint[] | null;
}

export type PreflightCode = 'no_finish' | 'no_start' | 'self_cross' | 'gate_far_from_route';
export type PreflightSeverity = 'warning' | 'error';

export interface PreflightIssue {
	courseId: string;
	code: PreflightCode;
	severity: PreflightSeverity;
	/** For gate_far_from_route: which line. */
	which?: GateWhich;
}

/**
 * The Arm (or window-open) preflight, #1305's table:
 *
 *   condition                               gun modes   self-timed
 *   no finish line and no finish point      warning     error
 *   no start line                           -           error
 *   finish_line_self_cross                  warning     error
 *   organiser line > 100 m from the route   warning     warning
 *
 * A course with no route has nothing to measure an organiser line against.
 */
export function racePreflight(courses: readonly PreflightCourse[], mode: SessionStartMode): PreflightIssue[] {
	const selfTimed = mode === 'self_timed';
	const out: PreflightIssue[] = [];
	for (const c of courses) {
		if (c.finishGate === null && !c.hasFinishPoint) {
			out.push({ courseId: c.id, code: 'no_finish', severity: selfTimed ? 'error' : 'warning' });
		}
		if (selfTimed && c.startGate === null) {
			out.push({ courseId: c.id, code: 'no_start', severity: 'error' });
		}
		if (c.selfCross) {
			out.push({ courseId: c.id, code: 'self_cross', severity: selfTimed ? 'error' : 'warning' });
		}
		for (const which of ['start', 'finish'] as const) {
			const gate = which === 'start' ? c.startGate : c.finishGate;
			if (gate === null || gate.source !== 'organiser' || c.route === null) continue;
			const rel = gateRouteRelation(gate, c.route);
			if (rel !== null && rel.distanceM > COURSE_GATE_ROUTE_WARN_M) {
				out.push({ courseId: c.id, code: 'gate_far_from_route', severity: 'warning', which });
			}
		}
	}
	return out;
}

/** Whether any issue stops the race from being armed. */
export function preflightBlocks(issues: readonly PreflightIssue[]): boolean {
	return issues.some((i) => i.severity === 'error');
}
