/**
 * Segment-effort extraction (decisions §37).
 *
 * v1 segments are slices of a *saved route* — `(start_distance_m,
 * end_distance_m)`. To produce an effort time for a run that follows
 * the route, we walk the run's track once, accumulate cumulative
 * distance via haversine, and record the timestamps at the moments
 * cumulative distance crosses `start_distance_m` and `end_distance_m`.
 *
 * Every position read off the run track is its LINE position
 * (`runs/track_line.ts`): the smoother's fix when the stored waypoint carries
 * both halves of it, else the raw one. Raw zig-zag inflates the hop-summed
 * distance, which moves the crossings and trips the end-to-end guard on a run
 * that did follow the segment. Timestamps are untouched — the crossings still
 * interpolate between the same fixes' `ts`.
 *
 * Pure module — no Supabase, no DOM. Stress-tested in segments.test.ts.
 */

import type { GlobalSegmentMatchedBy, TrackPoint } from '../types';
import {
	GATE_REJECT_GAP_S,
	GateCrossingDetector,
	gateProjection,
	gateUsable,
	type Gate,
	type GateCrossing,
} from '../geo/gate_crossing';
import { COURSE_GATE_BOX_DEPTH_M, gateTimingEdges } from '../races/course_gates';
import { haversineMetres } from '../geo/haversine';
import { unwrapLonDeg } from '../routes/geo';
import { lineLat, lineLng, trackLine } from '../runs/track_line';

export interface SegmentSlice {
	start_distance_m: number;
	end_distance_m: number;
}

export interface EffortResult {
	time_seconds: number;
	started_at: string; // ISO from the start crossing
}

/**
 * Computes the elapsed time over a (start, end) distance window of a
 * run track. Returns null when the track is too short to cover the
 * segment, has no timestamps, or is too sparsely sampled to produce
 * a meaningful effort (median sample distance > segment length / 5,
 * per §37 trade-off 2).
 */
export function computeEffortFromTrack(
	track: TrackPoint[],
	segment: SegmentSlice,
): EffortResult | null {
	return computeEffortsFromTrack(track, [segment])[0];
}

/**
 * Times a run track over many segment slices at once, returning one result
 * per input slice. Identical per-slice semantics to `computeEffortFromTrack`,
 * which delegates here.
 *
 * Everything expensive here is a property of the TRACK, not of the slice —
 * the cumulative-distance array and the median sample step the sparsity guard
 * compares against. Calling the single-slice form in a loop rebuilt and
 * re-sorted both per slice, so a run over a segmented route cost
 * O(segments x points log points): a 100k-point ultra over a 50-segment route
 * spent ~600 ms of blocked main thread on run-detail. Measured once here, the
 * per-slice work is two binary searches.
 *
 * Mirrors `computeEffortsFromTrack` in
 * `apps/mobile_android/lib/segments.dart`.
 */
export function computeEffortsFromTrack(
	track: TrackPoint[],
	segments: readonly SegmentSlice[],
): (EffortResult | null)[] {
	const out: (EffortResult | null)[] = new Array(segments.length).fill(null);
	if (track.length < 2 || segments.length === 0) return out;
	const index = distanceIndex(track);
	for (let i = 0; i < segments.length; i++) {
		out[i] = effortFromIndex(track, index, segments[i]);
	}
	return out;
}

interface TrackDistanceIndex {
	cum: Float64Array;
	/** Median non-zero sample step; null when the track never moved. */
	medianStep: number | null;
}

function distanceIndex(track: TrackPoint[]): TrackDistanceIndex {
	const cum = new Float64Array(track.length);
	const steps: number[] = [];
	for (let i = 1; i < track.length; i++) {
		const a = track[i - 1];
		const b = track[i];
		const d = haversineMetres(lineLat(a), lineLng(a), lineLat(b), lineLng(b));
		cum[i] = cum[i - 1] + d;
		if (d > 0) steps.push(d);
	}
	if (steps.length === 0) return { cum, medianStep: null };
	steps.sort((a, b) => a - b);
	return { cum, medianStep: steps[Math.floor(steps.length / 2)] };
}

function effortFromIndex(
	track: TrackPoint[],
	index: TrackDistanceIndex,
	segment: SegmentSlice,
): EffortResult | null {
	const segLen = segment.end_distance_m - segment.start_distance_m;
	if (segLen <= 0) return null;

	const { cum, medianStep } = index;
	if (cum[cum.length - 1] < segment.end_distance_m) return null;
	if (medianStep == null) return null;

	// Sparsity guard: median sample step must be at least 5× smaller
	// than the segment so the start / end crossings are well-resolved.
	if (medianStep > segLen / 5) return null;

	const startTs = timestampAtDistance(track, cum, segment.start_distance_m);
	const endTs = timestampAtDistance(track, cum, segment.end_distance_m);
	if (startTs == null || endTs == null) return null;

	const elapsed = (endTs - startTs) / 1000;
	if (!(elapsed > 0)) return null;

	return {
		time_seconds: elapsed,
		started_at: new Date(startTs).toISOString(),
	};
}

/**
 * The catalogue matcher's version. Bump it whenever a change would time a run
 * differently, so the owner-on-view fallback re-matches efforts an older
 * matcher wrote (`runs.metadata.global_segments_matcher_version`, issue
 * #1308). 1 was the circles-only matcher; 2 times a segment with a usable pair
 * of lines by its line crossings and reads only on-track fixes; 3 times every
 * complete lap of a loop, so a run's fastest lap is its effort (§ 2465); 4
 * times by the drawn start and finish boxes, with GPS slack at either end of
 * the recording and a longer gap across the finish (§ 2589).
 */
export const GLOBAL_SEGMENT_MATCHER_VERSION = 4;

/**
 * How far past the start box's exit edge a recording's first fix, or short of
 * the finish box a recording's last stretch, may sit and still count: the
 * GPS error of a phone standing at the line (decisions § 2589).
 */
export const GLOBAL_SEGMENT_BOX_SLACK_M = 5;

/**
 * The longest gap between two fixes across the finish edge that still
 * finishes, when the straight-line speed across it is within
 * GLOBAL_SEGMENT_GAP_SPEED_MIN..MAX of the runner's average since the start.
 * Up to GATE_REJECT_GAP_S any crossing counts, as for every line.
 */
export const GLOBAL_SEGMENT_FINISH_MAX_GAP_S = 300;
const BOX_REACH_M = COURSE_GATE_BOX_DEPTH_M + GLOBAL_SEGMENT_BOX_SLACK_M;
export const GLOBAL_SEGMENT_GAP_SPEED_MIN = 0.4;
export const GLOBAL_SEGMENT_GAP_SPEED_MAX = 1.5;

/** Covered distance between the start and end must be within this fraction
 *  of the segment's stored length, whichever way the segment is matched. */
export const GLOBAL_SEGMENT_LENGTH_TOLERANCE = 0.25;

/** A free-standing catalogue-segment geometry (the global/famous-segment
 *  layer — decisions §232). Unlike a route slice, it carries its own
 *  polyline, so matching keys off the run passing the segment's start
 *  then its end rather than a distance-along-a-route window. */
export interface GlobalSegmentGeometry {
	/** Ordered lat/lng points of the segment's own polyline. */
	points: { lat: number; lng: number }[];
	/** The catalogue's stored length in metres — the end-to-end guard. */
	distance_m: number;
	/** Ordered points the run must also pass, in order, within the match
	 *  tolerance between the start and end crossings (a park course's
	 *  `checkpoints`, decisions § 2383). The 25% length guard alone lets a
	 *  runner cut a fifth off an out-and-back or take a cut-through on a
	 *  trail network; a checkpoint on the far side of the cut refuses it. */
	checkpoints?: { lat: number; lng: number }[];
	/** The segment's start and end lines (`global_segments.start_gate_*` /
	 *  `end_gate_*`, decisions § 2402). When both are usable the segment is
	 *  matched by its line crossings ONLY; otherwise by the circles. */
	startGate?: Gate | null;
	endGate?: Gate | null;
}

export interface GlobalSegmentEffortResult extends EffortResult {
	matched_by: GlobalSegmentMatchedBy;
}

/** The line columns of a `global_segments` row. */
export interface GlobalSegmentGateColumns {
	start_gate_lat?: number | null;
	start_gate_lng?: number | null;
	start_gate_bearing_deg?: number | null;
	start_gate_half_width_m?: number | null;
	end_gate_lat?: number | null;
	end_gate_lng?: number | null;
	end_gate_bearing_deg?: number | null;
	end_gate_half_width_m?: number | null;
}

function finiteNumber(v: unknown): v is number {
	return typeof v === 'number' && Number.isFinite(v);
}

function gateOf(
	lat: unknown,
	lng: unknown,
	bearingDeg: unknown,
	halfWidthM: unknown,
): Gate | null {
	if (!finiteNumber(lat) || !finiteNumber(lng) || !finiteNumber(bearingDeg) || !finiteNumber(halfWidthM)) {
		return null;
	}
	return { lat, lng, bearingDeg, halfWidthM };
}

/**
 * A catalogue row as the matcher reads it: its polyline (`Number()` on each
 * coordinate and on the length, as the scorers always have), its lines, and
 * the park course checkpoints the caller read for it. The server processor
 * and the web fallback both build their geometries here, so they cannot
 * disagree about which segments have lines.
 */
export function globalSegmentGeometry(
	row: GlobalSegmentGateColumns & { waypoints: unknown; distance_m: number | string },
	checkpoints?: { lat: number; lng: number }[] | null,
): GlobalSegmentGeometry {
	const waypoints = Array.isArray(row.waypoints) ? row.waypoints : [];
	return {
		points: waypoints.map((w: { lat?: unknown; lng?: unknown } | null) => ({
			lat: Number(w?.lat),
			lng: Number(w?.lng),
		})),
		distance_m: Number(row.distance_m),
		checkpoints: checkpoints ?? undefined,
		startGate: gateOf(
			row.start_gate_lat,
			row.start_gate_lng,
			row.start_gate_bearing_deg,
			row.start_gate_half_width_m,
		),
		endGate: gateOf(row.end_gate_lat, row.end_gate_lng, row.end_gate_bearing_deg, row.end_gate_half_width_m),
	};
}

/** Both lines when both are usable, else null: the segment is then matched
 *  by the circles, never by one line and one circle. */
function segmentGates(segment: GlobalSegmentGeometry): { start: Gate; end: Gate } | null {
	const start = segment.startGate;
	const end = segment.endGate;
	if (!start || !end || !gateUsable(start) || !gateUsable(end)) return null;
	return { start, end };
}

/**
 * Whether a segment's end line is also its start line: the end line's centre
 * within the start line's reach, facing within 90° of it. A loop whose two
 * lines are derived from one closed polyline is the usual case (Beaver Lake);
 * a lollipop or out-and-back finishes facing the other way and is not, since
 * the runner turns before starting again. On such a loop the crossing that
 * finishes a lap also starts the next, whichever fix the start line's own
 * crossing falls on.
 */
export function linesChain(start: Gate, end: Gate): boolean {
	if (haversineMetres(start.lat, start.lng, end.lat, end.lng) > start.halfWidthM) return false;
	const turn = ((((end.bearingDeg - start.bearingDeg) % 360) + 540) % 360) - 180;
	return Math.abs(turn) < 90;
}

/**
 * Scores a run track against a free-standing catalogue-segment geometry
 * and returns the effort time, or null if the run didn't run it.
 *
 * Two rules, chosen per segment:
 *
 * - **Boxes** (a segment with a usable start and end line, decisions § 2402,
 *   § 2589): the start and finish boxes a course map draws
 *   (`gateTimingEdges`). The clock starts when the run leaves the start box
 *   forward and stops when it next enters the finish box, both interpolated
 *   between fixes, with the covered distance between them within 25% of the
 *   segment's length and every checkpoint passed in order between them. A
 *   recording whose first fix is already up to GLOBAL_SEGMENT_BOX_SLACK_M
 *   past the exit edge starts at that fix; one that ends in the finish box,
 *   or that slack short of it, without entering finishes where its last
 *   stretch there began. A gap across the finish edge longer than
 *   GATE_REJECT_GAP_S counts up to GLOBAL_SEGMENT_FINISH_MAX_GAP_S when it
 *   was crossed at about the runner's own pace. Every complete lap is a
 *   candidate and the fastest counts. Laps never overlap: once a lap closes,
 *   only a start at or after its finish can open the next, and on a loop
 *   whose end line is its start line but whose boxes are apart
 *   (`linesChain`) the finish itself opens it (decisions § 2465). A run
 *   that never leaves and enters the boxes is not matched by the circles
 *   instead: no circle fallback.
 * - **Circles** (no usable pair of lines): the v1 CURATED end-to-end match,
 *   NOT arbitrary-geometry HMM matching (deferred — see
 *   docs/features/segments.md): the run must approach the segment's START
 *   within `toleranceM`, then reach its END within `toleranceM` LATER in the
 *   track, with the same length guard and checkpoints, timed by
 *   `computeEffortFromTrack`'s own distance-window logic.
 *
 * Either way only on-track fixes (`trackLine`) are read, at their line
 * positions. Mirrors `computeGlobalSegmentEffort` in
 * `apps/mobile_android/lib/segments.dart`.
 */
export function computeGlobalSegmentEffort(
	track: TrackPoint[],
	segment: GlobalSegmentGeometry,
	toleranceM = 35,
): GlobalSegmentEffortResult | null {
	return computeGlobalSegmentEfforts(track, [segment], toleranceM)[0];
}

/**
 * Scores a run track against a whole catalogue of segment geometries in one
 * sweep, returning one result per input segment (null where the run didn't
 * run it). Identical per-segment semantics to `computeGlobalSegmentEffort`,
 * which delegates here.
 *
 * The batch shape is what makes catalogue scoring affordable. Scored
 * one-at-a-time, every segment paid two full-track haversine passes before
 * the check that rejects it, so the run-detail sweep over the 500-segment
 * catalogue (`GLOBAL_SEGMENT_SCORING_LIMIT`) was O(segments x trackPoints) —
 * seconds of blocked main thread on a long track, essentially all of it spent
 * measuring distances to segments on other continents. Here the track's
 * extent is measured once and each segment is rejected against it in constant
 * time, so only the handful of geometries that could plausibly match walk the
 * track at all.
 *
 * Mirrors `computeGlobalSegmentEfforts` in
 * `apps/mobile_android/lib/segments.dart`.
 */
export function computeGlobalSegmentEfforts(
	track: TrackPoint[],
	segments: readonly GlobalSegmentGeometry[],
	toleranceM = 35,
): (GlobalSegmentEffortResult | null)[] {
	const out: (GlobalSegmentEffortResult | null)[] = new Array(segments.length).fill(null);
	const line = trackLine(track);
	if (line.length < 2 || segments.length === 0) return out;

	const bounds = trackBounds(line);
	// Only built once a segment survives the extent test — a sweep that
	// rejects every segment must not pay a haversine pass at all.
	let index: TrackDistanceIndex | null = null;

	for (let i = 0; i < segments.length; i++) {
		const segment = segments[i];
		const pts = segment.points;
		if (pts.length < 2 || !(segment.distance_m > 0)) continue;
		const gates = segmentGates(segment);
		if (gates !== null) {
			// A box edge is crossed on the chord between two fixes, so inside
			// the track's extent, and a box edge, or a fix within the slack of
			// one, lies within its half-width, its depth and the slack of the
			// line's centre.
			const reach = BOX_REACH_M;
			if (!boundsAdmit(bounds, gates.start, gates.start.halfWidthM + reach)) continue;
			if (!boundsAdmit(bounds, gates.end, gates.end.halfWidthM + reach)) continue;
			if (index === null) index = distanceIndex(line);
			out[i] = scoreByGates(line, index, segment, gates.start, gates.end, toleranceM);
			continue;
		}
		const start = pts[0];
		const end = pts[pts.length - 1];
		if (!boundsAdmit(bounds, start, toleranceM)) continue;
		if (!boundsAdmit(bounds, end, toleranceM)) continue;
		if (index === null) index = distanceIndex(line);
		const eff = scoreAgainstTrack(line, index, segment, toleranceM);
		out[i] = eff === null ? null : { ...eff, matched_by: 'zone' };
	}
	return out;
}

interface PendingStart {
	crossing: GateCrossing;
	/** Track index of the fix before the crossing: checkpoints count from it. */
	fromIdx: number;
}

function scoreByGates(
	line: TrackPoint[],
	index: TrackDistanceIndex,
	segment: GlobalSegmentGeometry,
	startGate: Gate,
	endGate: Gate,
	toleranceM: number,
): GlobalSegmentEffortResult | null {
	const len = segment.distance_m;
	const minCovered = len * (1 - GLOBAL_SEGMENT_LENGTH_TOLERANCE);
	const maxCovered = len * (1 + GLOBAL_SEGMENT_LENGTH_TOLERANCE);
	const edges = gateTimingEdges(startGate, endGate);
	const exit = edges.startExit;
	const entry = edges.finishEntry;
	const startDetector = new GateCrossingDetector(exit);
	const endDetector = new GateCrossingDetector(entry);

	// Apart, the finish box is not the start box, so on a loop whose end line
	// is its start line the finish opens the next lap. A shared box is left
	// forward again to start the next.
	const chained = edges.layout === 'apart' && linesChain(startGate, endGate);
	let pending: PendingStart[] = [];
	let best = null as { startMs: number; endMs: number } | null;
	let prevIdx = -1;
	let prevMs = -Infinity;
	// The fixes since the last one outside the finish box and its slack.
	let tailIdx = -1;
	let tailMs = NaN;
	let tailGap: FixGap = { fromIdx: -1, fromMs: NaN, gapS: 0 };
	let prevEntryS = NaN;

	const pick = (endCoveredM: number, endIdx: number, endMs: number, gap: FixGap): PendingStart | null => {
		pending = pending.filter((s) => endCoveredM - s.crossing.coveredM <= maxCovered);
		// Pending starts are in time order, so the last valid one is the latest
		// start and so the fastest lap ending here.
		let picked: PendingStart | null = null;
		for (const s of pending) {
			if (endCoveredM - s.crossing.coveredM < minCovered) continue;
			if (!(endMs > s.crossing.tMs)) continue;
			if (gap.gapS > GATE_REJECT_GAP_S && !plausibleGap(s, index.cum, gap, endIdx)) continue;
			if (!passesCheckpoints(line, segment.checkpoints, s.fromIdx, endIdx, toleranceM)) continue;
			picked = s;
		}
		return picked;
	};
	const record = (startMs: number, endMs: number) => {
		if (best === null || endMs - startMs < best.endMs - best.startMs) best = { startMs, endMs };
	};

	for (let i = 0; i < line.length; i++) {
		const p = line[i];
		const tMs = p.ts ? Date.parse(p.ts) : NaN;
		const lat = lineLat(p);
		const lng = lineLng(p);
		// The detectors drop these too; skipping them here keeps prevIdx on
		// the fix the detectors last accepted.
		if (!Number.isFinite(tMs) || !Number.isFinite(lat) || !Number.isFinite(lng) || tMs <= prevMs) {
			continue;
		}
		const fix = { lat, lng, tMs, coveredM: index.cum[i] };
		const endCrossing = endDetector.offer(fix);
		const startCrossing = startDetector.offer(fix);

		const gap: FixGap = { fromIdx: prevIdx, fromMs: prevMs, gapS: (tMs - prevMs) / 1000 };
		const gapS = gap.gapS;
		const inFinish = gateProjection(entry, lat, lng);
		if (inFinish.s >= -GLOBAL_SEGMENT_BOX_SLACK_M && inFinish.s <= edges.depthM && Math.abs(inFinish.u) <= entry.halfWidthM) {
			if (tailIdx < 0) {
				tailIdx = i;
				tailMs = tMs;
				tailGap = gap;
			}
		} else {
			tailIdx = -1;
		}

		const entered =
			endCrossing !== null && endCrossing.direction === 'forward'
				? endCrossing
				: gapS > GATE_REJECT_GAP_S && gapS <= GLOBAL_SEGMENT_FINISH_MAX_GAP_S
					? enteredAcrossGap(
							prevEntryS,
							inFinish,
							entry.halfWidthM,
							{ tMs: prevMs, coveredM: index.cum[prevIdx] },
							fix,
							pending[pending.length - 1],
						)
					: null;
		prevEntryS = inFinish.s;

		let closedBy: GateCrossing | null = null;
		if (entered !== null) {
			const chosen = pick(entered.coveredM, i, entered.tMs, gap);
			if (chosen !== null) {
				record(chosen.crossing.tMs, entered.tMs);
				// Laps never overlap: nothing that started before this finish
				// can start the next lap.
				pending = [];
				closedBy = entered;
			}
		}
		if (closedBy !== null && chained) pending.push({ crossing: closedBy, fromIdx: prevIdx });
		if (
			startCrossing !== null &&
			startCrossing.direction === 'forward' &&
			(closedBy === null || startCrossing.tMs >= closedBy.tMs)
		) {
			pending.push({ crossing: startCrossing, fromIdx: prevIdx });
		} else if (prevIdx < 0) {
			// A recording begun on the line: its first fix just past the exit
			// edge starts the clock there.
			const atStart = gateProjection(exit, lat, lng);
			if (atStart.s >= 0 && atStart.s <= GLOBAL_SEGMENT_BOX_SLACK_M && Math.abs(atStart.u) <= exit.halfWidthM) {
				pending.push({ crossing: firstFixStart(fix, atStart.u), fromIdx: i });
			}
		}
		prevIdx = i;
		prevMs = tMs;
	}

	// A recording that ends in the finish box, or just short of it, without
	// having crossed into it finishes where its last stretch there began.
	if (tailIdx >= 0 && pending.length > 0) {
		const chosen = pick(index.cum[tailIdx], tailIdx, tailMs, tailGap);
		if (chosen !== null) record(chosen.crossing.tMs, tailMs);
	}

	if (best === null) return null;
	const { startMs, endMs } = best;
	return {
		time_seconds: (endMs - startMs) / 1000,
		started_at: new Date(Math.round(startMs)).toISOString(),
		matched_by: 'gate',
	};
}

/**
 * The finish edge entered across a gap the line rule refuses: the fix before
 * it short of the edge, the fix after it in the finish box's lane at or past
 * the edge. The path inside the gap is unknown, and the straight line across
 * it cuts the bend before a finish, so the entry is timed back from the fix
 * after the gap at the runner's average pace since `since` (the latest
 * pending start), within the gap.
 */
function enteredAcrossGap(
	prevS: number,
	cur: { s: number; u: number },
	halfWidthM: number,
	prev: { tMs: number; coveredM: number },
	fix: { tMs: number; coveredM: number },
	since: PendingStart | undefined,
): GateCrossing | null {
	if (since === undefined || !(prevS < 0) || cur.s < 0 || Math.abs(cur.u) > halfWidthM) return null;
	const paceS = (prev.tMs - since.crossing.tMs) / 1000;
	const paceM = prev.coveredM - since.crossing.coveredM;
	if (!(paceS > 0) || !(paceM > 0)) return null;
	const backS = cur.s / (paceM / paceS);
	const tMs = Math.max(prev.tMs, fix.tMs - backS * 1000);
	const f = (tMs - prev.tMs) / (fix.tMs - prev.tMs);
	return {
		direction: 'forward',
		fraction: f,
		tMs,
		coveredM: Math.max(prev.coveredM, fix.coveredM - cur.s),
		offsetM: cur.u,
		gapped: true,
	};
}

function firstFixStart(fix: { tMs: number; coveredM: number }, offsetM: number): GateCrossing {
	return { direction: 'forward', fraction: 0, tMs: fix.tMs, coveredM: fix.coveredM, offsetM, gapped: false };
}

/** The fixes either side of a step in the track, and the seconds between them. */
interface FixGap {
	fromIdx: number;
	fromMs: number;
	gapS: number;
}

/**
 * Whether a gap of more than GATE_REJECT_GAP_S before fix `toIdx` may still
 * finish: at most GLOBAL_SEGMENT_FINISH_MAX_GAP_S, and crossed at about the
 * runner's own pace, its straight-line speed within
 * GLOBAL_SEGMENT_GAP_SPEED_MIN..MAX of their average from `start` to the fix
 * before the gap.
 */
function plausibleGap(start: PendingStart, cum: Float64Array, gap: FixGap, toIdx: number): boolean {
	if (gap.gapS > GLOBAL_SEGMENT_FINISH_MAX_GAP_S || gap.fromIdx < 0) return false;
	const soFarS = (gap.fromMs - start.crossing.tMs) / 1000;
	const soFarM = cum[gap.fromIdx] - start.crossing.coveredM;
	if (!(soFarS > 0) || !(soFarM > 0)) return false;
	const avg = soFarM / soFarS;
	const across = (cum[toIdx] - cum[gap.fromIdx]) / gap.gapS;
	return across >= GLOBAL_SEGMENT_GAP_SPEED_MIN * avg && across <= GLOBAL_SEGMENT_GAP_SPEED_MAX * avg;
}

function scoreAgainstTrack(
	track: TrackPoint[],
	index: TrackDistanceIndex,
	segment: GlobalSegmentGeometry,
	toleranceM: number,
): EffortResult | null {
	const cum = index.cum;
	const pts = segment.points;
	const start = pts[0];
	const end = pts[pts.length - 1];

	// Nearest run-track index to the segment start.
	let startIdx = -1;
	let startBest = Infinity;
	for (let i = 0; i < track.length; i++) {
		const d = haversineMetres(lineLat(track[i]), lineLng(track[i]), start.lat, start.lng);
		if (d < startBest) {
			startBest = d;
			startIdx = i;
		}
	}
	if (startIdx < 0 || startBest > toleranceM) return null;

	// Nearest run-track index to the segment end, AFTER the start crossing.
	let endIdx = -1;
	let endBest = Infinity;
	for (let i = startIdx + 1; i < track.length; i++) {
		const d = haversineMetres(lineLat(track[i]), lineLng(track[i]), end.lat, end.lng);
		if (d < endBest) {
			endBest = d;
			endIdx = i;
		}
	}
	if (endIdx < 0 || endBest > toleranceM) return null;

	const dStart = cum[startIdx];
	const dEnd = cum[endIdx];
	if (dEnd <= dStart) return null;

	// End-to-end guard: the covered distance must be ~the segment length,
	// so a straight-line shortcut between distant start/end points isn't
	// mistaken for running the segment.
	if (Math.abs(dEnd - dStart - segment.distance_m) / segment.distance_m > GLOBAL_SEGMENT_LENGTH_TOLERANCE) {
		return null;
	}

	if (!passesCheckpoints(track, segment.checkpoints, startIdx, endIdx, toleranceM)) return null;

	return effortFromIndex(track, index, {
		start_distance_m: dStart,
		end_distance_m: dEnd,
	});
}

/**
 * Whether the track passes every checkpoint, in order, between the start and
 * end crossings. Each checkpoint takes the FIRST in-tolerance track index at
 * or after the previous one's, so a checkpoint only reachable by doubling back
 * past a later one fails rather than matching out of order.
 */
function passesCheckpoints(
	track: TrackPoint[],
	checkpoints: readonly { lat: number; lng: number }[] | undefined,
	startIdx: number,
	endIdx: number,
	toleranceM: number,
): boolean {
	if (!checkpoints || checkpoints.length === 0) return true;
	let cursor = startIdx;
	for (const cp of checkpoints) {
		let hit = -1;
		for (let i = cursor; i <= endIdx; i++) {
			if (haversineMetres(lineLat(track[i]), lineLng(track[i]), cp.lat, cp.lng) <= toleranceM) {
				hit = i;
				break;
			}
		}
		if (hit < 0) return false;
		cursor = hit;
	}
	return true;
}

/**
 * Latitude / longitude extent of a run track. Longitudes are unwrapped
 * around the first point (`geo.ts`), so a track straddling the antimeridian
 * stays one narrow interval instead of appearing to span the globe.
 */
interface TrackBounds {
	minLat: number;
	maxLat: number;
	refLon: number;
	minLon: number;
	maxLon: number;
}

/**
 * Metres per degree of latitude on the 6371 km sphere `haversineMetres`
 * uses is 111_195; the smaller figure here is deliberate, so every degree
 * window derived from a tolerance comes out slightly WIDER than the true
 * one. The extent test must never reject a segment the full scan would
 * have matched.
 */
const CONSERVATIVE_METRES_PER_DEG = 110_574;

function trackBounds(track: TrackPoint[]): TrackBounds {
	const refLon = lineLng(track[0]);
	let minLat = lineLat(track[0]);
	let maxLat = minLat;
	let minLon = refLon;
	let maxLon = refLon;
	for (let i = 1; i < track.length; i++) {
		const lat = lineLat(track[i]);
		if (lat < minLat) minLat = lat;
		else if (lat > maxLat) maxLat = lat;
		const lon = unwrapLonDeg(refLon, lineLng(track[i]));
		if (lon < minLon) minLon = lon;
		else if (lon > maxLon) maxLon = lon;
	}
	return { minLat, maxLat, refLon, minLon, maxLon };
}

/**
 * Whether any point of the track could lie within `toleranceM` of `point`.
 * Conservative by construction: `false` means every track point is provably
 * further away, `true` means "maybe, go and measure".
 *
 * Latitude is exact — spherical distance is never less than the meridian
 * separation. Longitude uses the tangent-meridian bound: everything within
 * an angular distance s of a point at latitude phi lies within
 * asin(sin s / cos phi) of its meridian, taken here as the linear s / cos phi.
 * That linearisation only under-states the window as the ratio approaches 1,
 * which cannot happen while the window is still under a degree — so past a
 * degree, where the test has stopped discriminating anyway, it admits.
 */
function boundsAdmit(
	bounds: TrackBounds,
	point: { lat: number; lng: number },
	toleranceM: number,
): boolean {
	const padLat = toleranceM / CONSERVATIVE_METRES_PER_DEG;
	if (point.lat < bounds.minLat - padLat || point.lat > bounds.maxLat + padLat) return false;

	const cosLat = Math.cos((point.lat * Math.PI) / 180);
	if (cosLat <= 0) return true;
	const padLon = padLat / cosLat;
	if (padLon >= 1) return true;

	const lon = unwrapLonDeg(bounds.refLon, point.lng);
	return lon >= bounds.minLon - padLon && lon <= bounds.maxLon + padLon;
}

/**
 * Linearly interpolates the timestamp (ms epoch) at the moment the
 * cumulative distance crosses `target`. Returns null when no two
 * adjacent points carry timestamps to bracket the crossing.
 */
function timestampAtDistance(
	track: TrackPoint[],
	cum: Float64Array,
	target: number,
): number | null {
	// `cum` is non-decreasing, so the first index reaching `target` is a
	// binary search rather than a walk from the start of the track.
	let lo = 1;
	let hi = track.length - 1;
	let found = -1;
	while (lo <= hi) {
		const mid = (lo + hi) >> 1;
		if (cum[mid] < target) {
			lo = mid + 1;
		} else {
			found = mid;
			hi = mid - 1;
		}
	}
	if (found > 0) {
		const i = found;
		const prev = cum[i - 1];
		const here = cum[i];
		const a = track[i - 1];
		const b = track[i];
		if (!a.ts || !b.ts) return null;
		const tA = Date.parse(a.ts);
		const tB = Date.parse(b.ts);
		if (Number.isNaN(tA) || Number.isNaN(tB)) return null;
		const span = here - prev;
		const frac = span > 0 ? (target - prev) / span : 0;
		return tA + (tB - tA) * frac;
	}
	return null;
}

/**
 * Standard competition rank for an ascending-time leaderboard. Tied
 * times share the lower rank; the next distinct time skips to its
 * natural ordinal position. Example: times [10, 10, 15] → [1, 1, 3].
 *
 * Pure — used by the `fetchSegmentLeaderboardTiered` leaderboard fetcher.
 * Mirrors the `assignCompetitionRanks` helper in
 * `apps/mobile_android/lib/segments.dart`.
 *
 * Caller must pass items pre-sorted ascending by `time_seconds`.
 */
export function assignCompetitionRanks<T extends { time_seconds: number }>(
	rows: readonly T[],
): Array<{ row: T; rank: number }> {
	const out: Array<{ row: T; rank: number }> = [];
	let lastTime = Number.NaN;
	let lastRank = 0;
	for (let i = 0; i < rows.length; i++) {
		const r = rows[i];
		const rank = r.time_seconds === lastTime ? lastRank : i + 1;
		lastTime = r.time_seconds;
		lastRank = rank;
		out.push({ row: r, rank });
	}
	return out;
}

/**
 * Strava-style age band labels — 5-year bins starting at 18-19, then
 * 20-24 / 25-29 / ... up to '75+'. Matches Strava + Garmin Connect.
 * The migration's `segment_leaderboard_tiered` RPC accepts any of
 * these strings; pass `null` for "all ages".
 *
 * Lives in this pure module (not `data.ts`) so unit tests can pin
 * its shape without dragging in the SvelteKit `$app/env`-bound supabase
 * client.
 */
export const SEGMENT_AGE_BANDS = [
	'18-19',
	'20-24',
	'25-29',
	'30-34',
	'35-39',
	'40-44',
	'45-49',
	'50-54',
	'55-59',
	'60-64',
	'65-69',
	'70-74',
	'75+',
] as const;
export type SegmentAgeBand = (typeof SEGMENT_AGE_BANDS)[number];

export type SegmentGenderFilter = 'male' | 'female';

/**
 * Tooltip / aria-label for the KOM/QOM crown badge. Describes which
 * tier the rank-1 holder owns ("Fastest woman 35-39", "Fastest
 * overall", etc.) given the active filter. Mirrors
 * `apps/mobile_android/lib/segments.dart#crownLabel`.
 */
export function crownLabel(
	genderFilter: SegmentGenderFilter | null,
	ageFilter: SegmentAgeBand | null,
): string {
	const subject =
		genderFilter == null ? null : genderFilter === 'male' ? 'man' : 'woman';
	if (subject == null && ageFilter == null) return 'Fastest overall';
	if (subject != null && ageFilter == null) return `Fastest ${subject}`;
	if (subject == null && ageFilter != null) return `Fastest ${ageFilter}`;
	return `Fastest ${subject} ${ageFilter}`;
}
