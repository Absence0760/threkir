/**
 * Camera-path math for the 3D course flyover (#1270). Pure and deterministic:
 * the same course and distance always produce the same camera pose, so a
 * paused frame, a scrubbed frame and a played frame agree.
 *
 * Every lookup is a binary search over the precomputed cumulative distances,
 * because playback asks for a pose every animation frame and an ultra course
 * carries tens of thousands of points.
 *
 * Web-only (decisions §24), so no Dart twin.
 */
import { lonDeltaDeg, wrapLonDeg } from './geo';
import { haversineMetres } from '../runs/run_stats';
import { MILE_METRES } from '../runs/race_day';
import { courseDistanceScale } from './official_distance';

export interface PathPoint {
	lat: number;
	lng: number;
	ele: number | null;
}

export interface FlyoverPath {
	points: PathPoint[];
	cumM: number[];
	totalM: number;
}

export interface CameraPose {
	center: [number, number];
	bearing: number;
	lookAt: [number, number];
}

export interface DistanceMarker {
	label: number;
	dM: number;
	lat: number;
	lng: number;
}

export const FLYOVER_SPEEDS: readonly number[] = [100, 250, 500, 1000];
export const DEFAULT_FLYOVER_SPEED_MPS = 250;

const DEFAULT_LOOK_AHEAD_M = 300;
const DEFAULT_SMOOTHING_M = 400;
const M_PER_DEG_LAT = 111320;

export function buildFlyoverPath(points: readonly PathPoint[]): FlyoverPath {
	const kept: PathPoint[] = [];
	const cumM: number[] = [];
	let total = 0;
	for (const p of points) {
		if (!Number.isFinite(p.lat) || !Number.isFinite(p.lng)) continue;
		const ele = p.ele !== null && Number.isFinite(p.ele) ? p.ele : null;
		const prev = kept[kept.length - 1];
		if (prev && prev.lat === p.lat && prev.lng === p.lng) {
			if (prev.ele === null && ele !== null) prev.ele = ele;
			continue;
		}
		if (prev) total += haversineMetres(prev.lat, prev.lng, p.lat, p.lng);
		kept.push({ lat: p.lat, lng: p.lng, ele });
		cumM.push(total);
	}
	return { points: kept, cumM, totalM: total };
}

/** Throws on an empty path: there is no position to give, and a made-up one would fly the camera to 0,0. */
export function pointAtDistance(
	path: FlyoverPath,
	dM: number,
): { lat: number; lng: number; ele: number | null; index: number } {
	const { points, cumM } = path;
	if (points.length === 0) throw new RangeError('pointAtDistance: empty flyover path');
	const d = clampDistance(dM, path.totalM);
	const last = points.length - 1;
	if (last === 0 || d >= path.totalM) {
		const p = points[last];
		return { lat: p.lat, lng: p.lng, ele: p.ele, index: last };
	}
	const i = segmentIndex(cumM, d);
	const a = points[i];
	const b = points[i + 1];
	const segLen = cumM[i + 1] - cumM[i];
	const t = segLen > 0 ? (d - cumM[i]) / segLen : 0;
	return {
		lat: a.lat + (b.lat - a.lat) * t,
		lng: wrapLonDeg(a.lng + lonDeltaDeg(a.lng, b.lng) * t),
		ele: lerpNullable(a.ele, b.ele, t),
		index: i,
	};
}

/**
 * The bearing is the length-weighted average of the path's segment headings
 * over a window centred on `dM`, summed as unit vectors so a heading of 359°
 * and one of 1° average to 0° rather than 180°. A short switchback inside the
 * window cancels out instead of whipping the camera round.
 *
 * A reversal longer than the window does not cancel: the summed vector passes
 * through zero and would flip the camera 180° in a frame, so the smoothed
 * heading is also turn-rate limited along the course.
 * `smoothingM: 0` is the raw segment heading, unsmoothed and unlimited.
 */
export function cameraAt(
	path: FlyoverPath,
	dM: number,
	opts: { lookAheadM?: number; smoothingM?: number } = {},
): CameraPose {
	const lookAheadM = nonNegative(opts.lookAheadM, DEFAULT_LOOK_AHEAD_M);
	const smoothingM = nonNegative(opts.smoothingM, DEFAULT_SMOOTHING_M);
	const d = clampDistance(dM, path.totalM);
	const here = pointAtDistance(path, d);
	const ahead = pointAtDistance(path, Math.min(path.totalM, d + lookAheadM));
	const center: [number, number] = [here.lng, here.lat];
	const lookAt: [number, number] = [ahead.lng, ahead.lat];
	const bearing =
		smoothingM > 0 && path.totalM > 0
			? normalizeBearing(lookupBearing(bearingTable(path, smoothingM), d))
			: windowBearing(path, d, smoothingM, lookAheadM);
	return { center, bearing, lookAt };
}

const BEARING_STEP_M = 5;
const MAX_TURN_DEG_PER_M = 0.6;

interface BearingTable {
	stepM: number;
	totalM: number;
	deg: Float64Array;
}

const bearingTables = new WeakMap<FlyoverPath, Map<number, BearingTable>>();

function bearingTable(path: FlyoverPath, smoothingM: number): BearingTable {
	let bySmoothing = bearingTables.get(path);
	if (!bySmoothing) {
		bySmoothing = new Map();
		bearingTables.set(path, bySmoothing);
	}
	const cached = bySmoothing.get(smoothingM);
	if (cached && cached.totalM === path.totalM) return cached;
	const table = buildBearingTable(path, smoothingM);
	bySmoothing.set(smoothingM, table);
	return table;
}

/** Unwrapped degrees at `sampleAt(k)`, so a turn through north is a run of numbers, not a jump from 359 to 0. */
function buildBearingTable(path: FlyoverPath, smoothingM: number): BearingTable {
	const totalM = path.totalM;
	const n = Math.ceil(totalM / BEARING_STEP_M);
	const at = (k: number) => Math.min(totalM, k * BEARING_STEP_M);
	const raw = new Float64Array(n + 1);
	for (let k = 0; k <= n; k++) {
		const d = at(k);
		const deg = windowBearing(path, d, smoothingM, DEFAULT_LOOK_AHEAD_M);
		raw[k] = k === 0 ? deg : raw[k - 1] + shortestTurn(raw[k - 1], deg);
	}
	const forward = new Float64Array(n + 1);
	forward[0] = raw[0];
	for (let k = 1; k <= n; k++) {
		const limit = MAX_TURN_DEG_PER_M * (at(k) - at(k - 1));
		forward[k] = forward[k - 1] + clampAbs(raw[k] - forward[k - 1], limit);
	}
	const backward = new Float64Array(n + 1);
	backward[n] = raw[n];
	for (let k = n - 1; k >= 0; k--) {
		const limit = MAX_TURN_DEG_PER_M * (at(k + 1) - at(k));
		backward[k] = backward[k + 1] + clampAbs(raw[k] - backward[k + 1], limit);
	}
	const deg = new Float64Array(n + 1);
	for (let k = 0; k <= n; k++) deg[k] = (forward[k] + backward[k]) / 2;
	return { stepM: BEARING_STEP_M, totalM, deg };
}

function lookupBearing(table: BearingTable, d: number): number {
	const { deg, stepM, totalM } = table;
	const last = deg.length - 1;
	const k = Math.min(last, Math.floor(d / stepM));
	if (k >= last) return deg[last];
	const from = k * stepM;
	const to = Math.min(totalM, (k + 1) * stepM);
	const t = to > from ? (d - from) / (to - from) : 0;
	return deg[k] + (deg[k + 1] - deg[k]) * t;
}

function windowBearing(path: FlyoverPath, d: number, smoothingM: number, lookAheadM: number): number {
	let [x, y] = windowHeading(path, d - smoothingM / 2, d + smoothingM / 2);
	if (x === 0 && y === 0) [x, y] = windowHeading(path, d, d + 1e-6);
	if (x === 0 && y === 0) {
		const ahead = pointAtDistance(path, Math.min(path.totalM, d + lookAheadM));
		[x, y] = planarUnit(pointAtDistance(path, d), ahead);
	}
	return toBearing(x, y);
}

/** Signed degrees in (-180, 180] from `from` to `to`. */
export function shortestTurn(from: number, to: number): number {
	const diff = (((to - from) % 360) + 540) % 360 - 180;
	return diff === -180 ? 180 : diff;
}

function clampAbs(v: number, limit: number): number {
	return Math.max(-limit, Math.min(limit, v));
}

function normalizeBearing(deg: number): number {
	const b = ((deg % 360) + 360) % 360;
	return b === 360 ? 0 : b;
}

/** With an [officialDistanceM], marker k is the course's km k, placed at k / scale along the line. */
export function distanceMarkers(
	path: FlyoverPath,
	unit: 'km' | 'mi',
	officialDistanceM?: number | null,
): DistanceMarker[] {
	const step = unit === 'mi' ? MILE_METRES : 1000;
	if (path.points.length < 2 || !(path.totalM > 0)) return [];
	const scale = courseDistanceScale(path.totalM, officialDistanceM);
	const count = Math.floor((path.totalM * scale) / step + 1e-9);
	const markers: DistanceMarker[] = [];
	for (let k = 1; k <= count; k++) {
		const dM = Math.min((k * step) / scale, path.totalM);
		const p = pointAtDistance(path, dM);
		markers.push({ label: k, dM, lat: p.lat, lng: p.lng });
	}
	return markers;
}

/** A negative or non-finite elapsed time or speed moves nothing — a skewed frame clock must not rewind the flight. */
export function advance(dM: number, elapsedMs: number, speedMps: number, totalM: number): number {
	if (!Number.isFinite(totalM) || totalM <= 0) return 0;
	const start = clampDistance(dM, totalM);
	if (!Number.isFinite(elapsedMs) || !Number.isFinite(speedMps)) return start;
	const step = Math.max(0, elapsedMs) * Math.max(0, speedMps) / 1000;
	return Math.min(totalM, start + step);
}

function clampDistance(dM: number, totalM: number): number {
	if (Number.isNaN(dM)) return 0;
	return Math.min(totalM, Math.max(0, dM));
}

function nonNegative(v: number | undefined, fallback: number): number {
	return v !== undefined && Number.isFinite(v) ? Math.max(0, v) : fallback;
}

/** Largest i with cumM[i] <= d, capped so a segment i..i+1 exists. */
function segmentIndex(cumM: readonly number[], d: number): number {
	let lo = 0;
	let hi = cumM.length - 2;
	while (lo < hi) {
		const mid = (lo + hi + 1) >> 1;
		if (cumM[mid] <= d) lo = mid;
		else hi = mid - 1;
	}
	return lo;
}

function windowHeading(path: FlyoverPath, fromM: number, toM: number): [number, number] {
	const { points, cumM } = path;
	if (points.length < 2) return [0, 0];
	const lo = Math.max(0, fromM);
	const hi = Math.min(path.totalM, toM);
	if (!(hi > lo)) return [0, 0];
	let x = 0;
	let y = 0;
	for (let i = segmentIndex(cumM, lo); i < points.length - 1 && cumM[i] < hi; i++) {
		const overlap = Math.min(hi, cumM[i + 1]) - Math.max(lo, cumM[i]);
		if (overlap <= 0) continue;
		const [ux, uy] = planarUnit(points[i], points[i + 1]);
		x += ux * overlap;
		y += uy * overlap;
	}
	const len = Math.hypot(x, y);
	return len > 1e-9 ? [x / len, y / len] : [0, 0];
}

/** Unit vector (east, north) from a to b in a local planar frame; [0, 0] when they coincide. */
function planarUnit(
	a: { lat: number; lng: number },
	b: { lat: number; lng: number },
): [number, number] {
	const midLat = ((a.lat + b.lat) / 2) * (Math.PI / 180);
	const east = lonDeltaDeg(a.lng, b.lng) * Math.cos(midLat) * M_PER_DEG_LAT;
	const north = (b.lat - a.lat) * M_PER_DEG_LAT;
	const len = Math.hypot(east, north);
	return len > 0 ? [east / len, north / len] : [0, 0];
}

function toBearing(east: number, north: number): number {
	if (east === 0 && north === 0) return 0;
	const deg = (Math.atan2(east, north) * 180) / Math.PI;
	const b = ((deg % 360) + 360) % 360;
	return b === 360 ? 0 : b;
}

function lerpNullable(a: number | null, b: number | null, t: number): number | null {
	if (a === null && b === null) return null;
	if (a === null) return b;
	if (b === null) return a;
	return a + (b - a) * t;
}
