/**
 * Route art: turn a freehand stroke drawn on the map into routable waypoints,
 * plan the snapping calls within the OSRM proxy's limits, and grade how close
 * the snapped route stays to the drawing (decisions § 2263).
 *
 * Pure and dependency-free beyond the geo helpers, so the builder's pointer
 * handling and network calls stay out of it. TS twin of
 * `apps/mobile_android/lib/route_art.dart` — same constants, same algorithm,
 * same outputs; the two suites carry the same cases.
 *
 * Coordinates are `[lng, lat]`, the shape OSRM and maplibre speak.
 */

import { lonDeltaDeg, unwrapLonDeg, wrapLonDeg } from './geo';
import { simplifyTrack } from './route_simplify';
import { snapToPolyline } from './route_snap';
import { haversineMetres } from '../runs/run_stats';

export type LngLat = [number, number];

/** The proxy's per-call coordinate ceiling (`MAX_ROUTE_COORDS`). */
export const ROUTE_ART_MAX_COORDS_PER_CALL = 60;
/** Five calls of 60 sharing their seam points: 1 + 5 × 59. */
export const ROUTE_ART_MAX_POINTS = 296;
/** Target gap between routed points before the budget forces it wider. */
export const ROUTE_ART_SPACING_M = 60;
/** Hand jitter below this is dropped before anything else runs. */
export const ROUTE_ART_MIN_STEP_M = 2;
export const ROUTE_ART_MIN_STROKE_M = 300;
export const ROUTE_ART_MAX_STROKE_M = 100_000;
/** A stroke ending this close to its start (share of its length) is a loop. */
export const ROUTE_ART_CLOSE_FRACTION = 0.08;
export const ROUTE_ART_CLOSE_MIN_M = 40;
export const ROUTE_ART_CLOSE_MAX_M = 250;
/** Evenly spaced samples taken along each line when grading. */
export const ROUTE_ART_SAMPLES = 101;
/** Tolerance is this share of the drawing's bounding-box diagonal, clamped. */
export const ROUTE_ART_TOLERANCE_FRACTION = 0.05;
export const ROUTE_ART_TOLERANCE_MIN_M = 25;
export const ROUTE_ART_TOLERANCE_MAX_M = 120;
/** Below this the match is refused rather than saved as a different shape. */
export const ROUTE_ART_MIN_SCORE = 60;
export const ROUTE_ART_CLOSE_SCORE = 85;
/** How far each drawn point may reach for a way, then the one retry's reach. */
export const ROUTE_ART_SNAP_RADIUS_M = 150;
export const ROUTE_ART_WIDE_SNAP_RADIUS_M = 400;
/** Draggable pins left on a matched drawing. */
export const ROUTE_ART_ANCHOR_SPACING_M = 500;
export const ROUTE_ART_MAX_ANCHORS = 12;

const BUDGET_ATTEMPTS = 24;
const BUDGET_GROWTH = 1.25;
const SEAM_DEDUPE_M = 1;

function dist(a: LngLat, b: LngLat): number {
	return haversineMetres(a[1], a[0], b[1], b[0]);
}

function lerp(a: LngLat, b: LngLat, f: number): LngLat {
	return [wrapLonDeg(a[0] + lonDeltaDeg(a[0], b[0]) * f), a[1] + (b[1] - a[1]) * f];
}

function clamp(v: number, lo: number, hi: number): number {
	return Math.min(hi, Math.max(lo, v));
}

export function polylineLengthM(line: LngLat[]): number {
	let total = 0;
	for (let i = 1; i < line.length; i++) total += dist(line[i - 1], line[i]);
	return total;
}

/**
 * Insert evenly spaced points so no gap exceeds `spacingM`. Every input
 * vertex is kept, so the corners simplification chose survive exactly.
 */
export function densifyLine(line: LngLat[], spacingM: number): LngLat[] {
	if (line.length < 2 || !(spacingM > 0)) return line.map((p) => [p[0], p[1]]);
	const out: LngLat[] = [];
	for (let i = 0; i < line.length - 1; i++) {
		const a = line[i];
		const b = line[i + 1];
		const n = Math.max(1, Math.ceil(dist(a, b) / spacingM));
		for (let k = 0; k < n; k++) out.push(lerp(a, b, k / n));
	}
	const last = line[line.length - 1];
	out.push([last[0], last[1]]);
	return out;
}

export type PreparedStroke =
	| { ok: true; points: LngLat[]; lengthM: number; closed: boolean; spacingM: number }
	| { ok: false; reason: 'too_short' | 'too_long' | 'too_complex' };

/**
 * Clean a raw stroke into at most [ROUTE_ART_MAX_POINTS] routable points:
 * drop invalid and jitter points, close a nearly-closed loop, simplify, then
 * densify. When the budget is exceeded the spacing and tolerance widen
 * together until it fits.
 */
export function prepareStroke(raw: LngLat[]): PreparedStroke {
	const clean: LngLat[] = [];
	for (const p of raw) {
		const [lng, lat] = p;
		if (!Number.isFinite(lng) || !Number.isFinite(lat)) continue;
		if (Math.abs(lng) > 180 || Math.abs(lat) > 90) continue;
		if (clean.length > 0 && dist(clean[clean.length - 1], p) < ROUTE_ART_MIN_STEP_M) continue;
		clean.push([lng, lat]);
	}
	if (clean.length < 2) return { ok: false, reason: 'too_short' };
	const lengthM = polylineLengthM(clean);
	if (lengthM < ROUTE_ART_MIN_STROKE_M) return { ok: false, reason: 'too_short' };
	if (lengthM > ROUTE_ART_MAX_STROKE_M) return { ok: false, reason: 'too_long' };

	const first = clean[0];
	const gap = dist(first, clean[clean.length - 1]);
	const closeWithin = clamp(
		lengthM * ROUTE_ART_CLOSE_FRACTION,
		ROUTE_ART_CLOSE_MIN_M,
		ROUTE_ART_CLOSE_MAX_M,
	);
	const closed = gap <= closeWithin;
	if (closed && gap > 0) {
		if (gap < ROUTE_ART_MIN_STEP_M) clean[clean.length - 1] = [first[0], first[1]];
		else clean.push([first[0], first[1]]);
	}

	const asTrack = clean.map(([lng, lat]) => ({ lat, lng }));
	let spacingM = ROUTE_ART_SPACING_M;
	for (let attempt = 0; attempt < BUDGET_ATTEMPTS; attempt++) {
		const simplified: LngLat[] = simplifyTrack(asTrack, spacingM / 4).map((p) => [p.lng, p.lat]);
		const points = densifyLine(simplified, spacingM);
		if (points.length <= ROUTE_ART_MAX_POINTS) {
			return { ok: true, points, lengthM, closed, spacingM };
		}
		spacingM *= BUDGET_GROWTH;
	}
	return { ok: false, reason: 'too_complex' };
}

export interface RouteBatch {
	/** Inclusive index of the first point in this call. */
	start: number;
	/** Inclusive index of the last point; the next call starts here. */
	end: number;
}

/**
 * Split `count` points into calls of at most `maxPerCall` coordinates. Each
 * call starts on the previous call's last point so the stitched route has no
 * gap at a seam.
 */
export function planRouteBatches(
	count: number,
	maxPerCall: number = ROUTE_ART_MAX_COORDS_PER_CALL,
): RouteBatch[] {
	if (count < 2 || maxPerCall < 2) return [];
	const out: RouteBatch[] = [];
	let start = 0;
	while (start < count - 1) {
		const end = Math.min(start + maxPerCall - 1, count - 1);
		out.push({ start, end });
		start = end;
	}
	return out;
}

/**
 * The OSRM-shaped path for one call: every point is a waypoint the route must
 * pass, each allowed `radiusM` to find a way.
 */
export function routeArtBatchPath(points: LngLat[], profile: 'foot' | 'car', radiusM: number): string {
	const coords = points.map(([lng, lat]) => `${lng},${lat}`).join(';');
	const radiuses = points.map(() => String(radiusM)).join(';');
	return `/route/v1/${profile}/${coords}?overview=full&geometries=geojson&radiuses=${radiuses}`;
}

/** Join per-call polylines, dropping a seam point the previous call ended on. */
export function stitchPolylines(parts: LngLat[][]): LngLat[] {
	const out: LngLat[] = [];
	for (const part of parts) {
		for (let i = 0; i < part.length; i++) {
			if (i === 0 && out.length > 0 && dist(out[out.length - 1], part[0]) < SEAM_DEDUPE_M) continue;
			out.push([part[i][0], part[i][1]]);
		}
	}
	return out;
}

/** `count` points at evenly spaced distances along `line`, both ends included. */
export function sampleAlong(line: LngLat[], count: number): LngLat[] {
	if (line.length === 0 || count < 1) return [];
	const total = polylineLengthM(line);
	if (count === 1 || total <= 0 || line.length === 1) {
		return Array.from({ length: count }, () => [line[0][0], line[0][1]] as LngLat);
	}
	const out: LngLat[] = [];
	let seg = 0;
	let segStart = 0;
	let segLen = dist(line[0], line[1]);
	for (let k = 0; k < count; k++) {
		const target = (total * k) / (count - 1);
		while (seg < line.length - 2 && segStart + segLen < target) {
			segStart += segLen;
			seg++;
			segLen = dist(line[seg], line[seg + 1]);
		}
		const f = segLen > 0 ? clamp((target - segStart) / segLen, 0, 1) : 0;
		out.push(lerp(line[seg], line[seg + 1], f));
	}
	return out;
}

/** How far "close" reaches for this drawing: a share of its size, clamped. */
export function fidelityToleranceM(drawn: LngLat[]): number {
	if (drawn.length === 0) return ROUTE_ART_TOLERANCE_MIN_M;
	const ref = drawn[0][0];
	let minLng = Infinity;
	let maxLng = -Infinity;
	let minLat = Infinity;
	let maxLat = -Infinity;
	for (const [lng, lat] of drawn) {
		const u = unwrapLonDeg(ref, lng);
		if (u < minLng) minLng = u;
		if (u > maxLng) maxLng = u;
		if (lat < minLat) minLat = lat;
		if (lat > maxLat) maxLat = lat;
	}
	const diag = haversineMetres(minLat, minLng, maxLat, maxLng);
	return clamp(
		diag * ROUTE_ART_TOLERANCE_FRACTION,
		ROUTE_ART_TOLERANCE_MIN_M,
		ROUTE_ART_TOLERANCE_MAX_M,
	);
}

export type FidelityVerdict = 'close' | 'rough' | 'poor';

export interface ArtFidelity {
	/** 0-100: the worse of coverage and precision, as a percentage. */
	score: number;
	/** Share of the drawing within tolerance of the route. */
	coverage: number;
	/** Share of the route within tolerance of the drawing. */
	precision: number;
	/** Mean distance from the drawing to the route, metres. */
	meanOffsetM: number;
	/** Largest distance either way, metres. */
	maxOffsetM: number;
	toleranceM: number;
	/** Route length over drawing length. */
	lengthRatio: number;
	verdict: FidelityVerdict;
}

export function fidelityVerdict(score: number): FidelityVerdict {
	if (score >= ROUTE_ART_CLOSE_SCORE) return 'close';
	if (score >= ROUTE_ART_MIN_SCORE) return 'rough';
	return 'poor';
}

function offsetM(p: LngLat, line: LngLat[]): number {
	return snapToPolyline({ lng: p[0], lat: p[1] }, line)?.offsetM ?? Infinity;
}

/**
 * Grade a matched route against the drawing. Coverage asks whether every part
 * of the drawing was reached; precision asks whether the route wandered off
 * it. The score is the worse of the two, because either failure alone draws
 * a different picture: a route that covers the shape plus a long detour, or
 * one that stays on the shape but skips half of it.
 */
export function drawingFidelity(drawn: LngLat[], matched: LngLat[]): ArtFidelity | null {
	if (drawn.length < 2 || matched.length < 2) return null;
	const drawnLen = polylineLengthM(drawn);
	const matchedLen = polylineLengthM(matched);
	if (drawnLen <= 0 || matchedLen <= 0) return null;

	const toleranceM = fidelityToleranceM(drawn);
	let covered = 0;
	let sumOffset = 0;
	let maxOffsetM = 0;
	for (const p of sampleAlong(drawn, ROUTE_ART_SAMPLES)) {
		const d = offsetM(p, matched);
		sumOffset += d;
		if (d > maxOffsetM) maxOffsetM = d;
		if (d <= toleranceM) covered++;
	}
	let precise = 0;
	for (const p of sampleAlong(matched, ROUTE_ART_SAMPLES)) {
		const d = offsetM(p, drawn);
		if (d > maxOffsetM) maxOffsetM = d;
		if (d <= toleranceM) precise++;
	}
	const coverage = covered / ROUTE_ART_SAMPLES;
	const precision = precise / ROUTE_ART_SAMPLES;
	const score = Math.round(100 * Math.min(coverage, precision));
	return {
		score,
		coverage,
		precision,
		meanOffsetM: sumOffset / ROUTE_ART_SAMPLES,
		maxOffsetM,
		toleranceM,
		lengthRatio: matchedLen / drawnLen,
		verdict: fidelityVerdict(score),
	};
}

/**
 * Indices of the pins left on a matched drawing: both ends, plus one each
 * time the route passes another `step` metres, with `step` widened so the
 * count never exceeds `maxAnchors`.
 */
export function artAnchorIndices(
	line: LngLat[],
	spacingM: number = ROUTE_ART_ANCHOR_SPACING_M,
	maxAnchors: number = ROUTE_ART_MAX_ANCHORS,
): number[] {
	if (line.length === 0) return [];
	if (line.length === 1) return [0];
	const total = polylineLengthM(line);
	const step = Math.max(spacingM, total / Math.max(1, maxAnchors - 1));
	const out = [0];
	let along = 0;
	let next = step;
	for (let i = 1; i < line.length - 1; i++) {
		along += dist(line[i - 1], line[i]);
		if (along >= next && total - along >= step / 2) {
			out.push(i);
			while (next <= along) next += step;
		}
	}
	out.push(line.length - 1);
	return out;
}

/** The slices of `line` between consecutive anchors, seam points shared. */
export function sliceAtAnchors(line: LngLat[], anchors: number[]): LngLat[][] {
	const out: LngLat[][] = [];
	for (let j = 0; j < anchors.length - 1; j++) {
		out.push(line.slice(anchors[j], anchors[j + 1] + 1).map((p) => [p[0], p[1]] as LngLat));
	}
	return out;
}
