import type { TrackPoint } from '../types';
import { lineLat, lineLng } from './track_line';
import { runAltitudeSeries } from './run_altitude';

/**
 * Whether every point of [track] carries the recorder's cumulative credited
 * distance (`distM`): finite, non-negative and never decreasing. All or
 * nothing, so a track that mixes stamped and unstamped points (an older
 * recorder's points ahead of a resumed session's) measures on positions
 * throughout rather than on two different axes.
 */
export function hasRecordedDistances(track: readonly TrackPoint[]): boolean {
	if (track.length < 2) return false;
	let prev = 0;
	for (const p of track) {
		const d = p?.distM;
		if (typeof d !== 'number' || !Number.isFinite(d) || d < prev) return false;
		prev = d;
	}
	return true;
}

/**
 * Distance along the run at each point of [track], metres: the axis splits
 * and moving time are measured on (docs/features/gps_distance.md § Splits and
 * moving time).
 *
 * A track whose every point carries `distM` uses it, scaled so the last point
 * reads [totalDistanceM] when that is given: the recorder's figure stops at
 * the last stored fix while the run's `distance_m` also counts what the
 * estimator credited after it, and the server recompute rewrites
 * `distance_m` without touching the stored track. Otherwise the hop-sum over
 * the line positions (the smoothed position when the fix carries one, else the
 * raw fix), unscaled, which is what every track before `distM` measures on.
 * Pass [totalDistanceM] only with the whole stored track (the owner's): a
 * privacy-clipped one ends short of the run and would be stretched.
 * Mirrors `trackCumulativeMetres` in `apps/mobile_android/lib/run_stats.dart`.
 */
export function trackCumulativeMetres(
	track: readonly TrackPoint[],
	totalDistanceM?: number | null
): number[] {
	const n = track.length;
	if (n === 0) return [];
	if (hasRecordedDistances(track)) {
		const last = track[n - 1].distM as number;
		const scale =
			totalDistanceM != null && Number.isFinite(totalDistanceM) && totalDistanceM > 0 && last > 0
				? totalDistanceM / last
				: 1;
		return track.map((p) => (p.distM as number) * scale);
	}
	const out = new Array<number>(n);
	out[0] = 0;
	for (let i = 1; i < n; i++) {
		const a = track[i - 1];
		const b = track[i];
		out[i] = out[i - 1] + haversineMetres(lineLat(a), lineLng(a), lineLat(b), lineLng(b));
	}
	return out;
}

/**
 * Moving time — elapsed with stops excluded, derived from a GPS track.
 *
 * Mirrors `apps/mobile_android/lib/run_stats.dart:movingTimeOf`. Both
 * clients compute this on demand at display time rather than storing it,
 * so the metric stays consistent if the algorithm is tuned later.
 *
 * Walks consecutive waypoint pairs, computes `speed = distance / time`
 * with distance read off `trackCumulativeMetres` (the estimator's credit
 * when the track carries it, so a stop the filter held still is not moving
 * time however far the raw fixes wandered), and counts only segments whose speed is at or above [minSpeedMps].
 * Default 0.5 m/s (~1.8 km/h) — slower than a slow walk but above the
 * noise floor when the runner is standing still.
 *
 * Returns seconds.
 */
export function movingTimeSeconds(
	track: TrackPoint[] | null | undefined,
	minSpeedMps = 0.5
): number {
	if (!track || track.length < 2) return 0;
	const cum = trackCumulativeMetres(track);
	let movingMs = 0;
	for (let i = 1; i < track.length; i++) {
		const a = track[i - 1];
		const b = track[i];
		if (!a.ts || !b.ts) continue;
		const dtMs = Date.parse(b.ts) - Date.parse(a.ts);
		if (!Number.isFinite(dtMs) || dtMs <= 0) continue;
		const distance = cum[i] - cum[i - 1];
		const speed = distance / (dtMs / 1000);
		if (speed >= minSpeedMps) movingMs += dtMs;
	}
	return Math.round(movingMs / 1000);
}


export interface Split {
	km: number;
	pace_s: number;
	distance_m: number;
	elevation_m: number | null;
}

/**
 * The shortest tail `computeRealSplits` will emit as a split of its own, in
 * metres. Below it the split table drops the leftover rather than printing a
 * pace derived from a few seconds over a few metres.
 */
export const SPLIT_TAIL_MIN_M = 50;

/**
 * Compute per-unit splits from a GPS track. Requires timestamps on track
 * points; returns [] when fewer than two points carry timestamps. Mirrors
 * the Android `run_detail_screen.dart` split logic.
 *
 * `tickMetres` is the split boundary length — 1000 for km splits,
 * 1609.344 for mile splits, so a miles-preference user gets mile-long
 * splits instead of km ones (mobile already does this via `tickLength`).
 * `pace_s` stays canonical seconds-per-km regardless of tick length; the
 * caller converts to the display unit (`formatPaceNoSuffix`).
 *
 * Elevation per split is the net gain/loss (positive = gain) over that
 * segment, read off `runAltitudeSeries` — the barometer when the run carries
 * one, else GPS altitude, never an off-track fix's — so it agrees with the
 * run's climb, the elevation chart and the 3D replay. The altitude at a
 * boundary is interpolated along the distance axis between the nearest points
 * that carry one, so a dropout is carried across exactly as the climb rule
 * carries it, and held flat past the first and last of them. Null for a split
 * wholly outside the stretch that carries an altitude, so on every split when
 * no point does.
 *
 * Distance is `trackCumulativeMetres(track, totalDistanceM)`: pass the run's
 * `distance_m` and a track that carries the recorder's `distM` ends its last
 * split on it.
 */
export function computeRealSplits(
	track: TrackPoint[],
	tickMetres = 1000,
	totalDistanceM?: number | null
): Split[] {
	// A tick of 0 put every boundary at 0 m, which the boundary loop below
	// re-crosses forever. The Dart twin returns [] for a non-positive tick.
	if (track.length < 2 || !(tickMetres > 0)) return [];
	const hasTs = track.some((p) => p.ts != null);
	if (!hasTs) return [];


	// Seed the first split's start time from the first point that actually
	// carries a parseable timestamp, not track[0]: a first GPS fix that lands
	// before the clock is stamped (ts missing on point 0, present after) would
	// otherwise seed NaN, fail the duration guard, and emit the first split at
	// pace 0:00 even though the run was timed from point 1 on. `hasTs`
	// guarantees at least one timed point exists.
	const firstTimed = track.find((p) => p.ts != null && Number.isFinite(Date.parse(p.ts)));
	const startMs = firstTimed ? Date.parse(firstTimed.ts as string) : NaN;

	const cum = trackCumulativeMetres(track, totalDistanceM);
	const elevationOf = splitElevationReader(runAltitudeSeries(track), cum);
	let cumDist = 0;
	let splitStart = { dist: 0, timeMs: startMs };
	const splits: Split[] = [];

	// Close the current split at cumulative distance `endDist`, using the
	// (interpolated) crossing time, then re-seed the next split from there.
	// Pace is normalised by the split's actual distance, so a split that isn't
	// exactly `tickMetres` still reports a correct per-km pace.
	const emit = (endDist: number, endTimeMs: number) => {
		const durationS =
			Number.isFinite(endTimeMs) && Number.isFinite(splitStart.timeMs)
				? (endTimeMs - splitStart.timeMs) / 1000
				: 0;
		const splitDist = endDist - splitStart.dist;
		const paceS = durationS > 0 && splitDist > 0 ? Math.round(durationS / (splitDist / 1000)) : 0;
		splits.push({
			km: splits.length + 1,
			pace_s: paceS,
			distance_m: Math.round(splitDist),
			elevation_m: elevationOf(splitStart.dist, endDist),
		});
		splitStart = { dist: endDist, timeMs: endTimeMs };
	};

	for (let i = 1; i < track.length; i++) {
		const a = track[i - 1];
		const b = track[i];
		const segStart = i === 1 ? 0 : cum[i - 1];
		cumDist = cum[i];
		const segDist = cumDist - segStart;
		const aMs = a.ts ? Date.parse(a.ts) : NaN;
		const bMs = b.ts ? Date.parse(b.ts) : NaN;

		// A single segment can straddle several tick boundaries when there is a
		// long gap between two fixes (a tunnel, a canyon/forest signal loss, or
		// a downsampled Strava/Garmin import). Emit a split AT each boundary,
		// interpolating the crossing time by the distance fraction along the
		// segment — so the gap becomes one correctly-sized split per tick
		// instead of one oversized split followed by zero-distance slivers.
		let boundaryDist = (splits.length + 1) * tickMetres;
		while (segDist > 0 && cumDist >= boundaryDist) {
			const f = (boundaryDist - segStart) / segDist;
			const crossMs = Number.isFinite(aMs) && Number.isFinite(bMs) ? aMs + f * (bMs - aMs) : bMs;
			emit(boundaryDist, crossMs);
			boundaryDist = (splits.length + 1) * tickMetres;
		}
	}

	// The tail after the last whole tick, emitted only when it is long enough
	// to carry a pace worth reading. Under the floor the duration is a handful
	// of seconds over a handful of metres, and dividing them prints a pace off
	// by an order of magnitude beside every real split in the table.
	//
	// The consequence is deliberate and stated here because the numbers are
	// visible: a run of 5.04 km renders five splits summing to 5,000 m, so the
	// split table's own total is up to `SPLIT_TAIL_MIN_M` short of the run's
	// headline distance. A wrong pace on a named row is worse than a total
	// that is under one percent light on a 5 km.
	if (splits.length > 0 || cumDist > 0) {
		const lastPoint = track[track.length - 1];
		const endTimeMs = lastPoint.ts ? Date.parse(lastPoint.ts) : NaN;
		if (cumDist - splitStart.dist > SPLIT_TAIL_MIN_M) {
			emit(cumDist, endTimeMs);
		}
	}

	return splits;
}

/**
 * The net elevation, whole metres, of the split from `start` to `end` along
 * the split axis: [cum] with the first point at 0, the axis the boundary loop
 * in `computeRealSplits` walks. The altitude at each end is linear between the
 * nearest points of [altitudes] that carry one, and held at the first / last
 * of them for a split that only partly overlaps the measured stretch. A split
 * wholly before the first or after the last altitude is null, not a held 0 m
 * that would read as measured. Twin of `_splitElevationReader` in
 * `run_stats.dart`.
 */
function splitElevationReader(
	altitudes: readonly (number | null)[],
	cum: readonly number[]
): (start: number, end: number) => number | null {
	const at: number[] = [];
	const alt: number[] = [];
	for (let i = 0; i < altitudes.length; i++) {
		const v = altitudes[i];
		if (v == null) continue;
		at.push(i === 0 ? 0 : cum[i]);
		alt.push(v);
	}
	if (alt.length === 0) return () => null;
	const altitudeAt = (d: number): number => {
		if (d <= at[0]) return alt[0];
		const last = at.length - 1;
		if (d >= at[last]) return alt[last];
		let lo = 0;
		let hi = last;
		while (hi - lo > 1) {
			const mid = (lo + hi) >> 1;
			if (at[mid] <= d) lo = mid;
			else hi = mid;
		}
		const span = at[hi] - at[lo];
		return span > 0 ? alt[lo] + ((d - at[lo]) / span) * (alt[hi] - alt[lo]) : alt[hi];
	};
	return (start, end) =>
		end <= at[0] || start >= at[at.length - 1] ? null : Math.round(altitudeAt(end) - altitudeAt(start));
}

/**
 * Great-circle distance between two lat/lng points, in metres.
 */
/**
 * Great-circle metres between two points. Exported so the twin contract with
 * `run_stats.dart`'s `haversineMetres` can be pinned on both sides — it was
 * private, which is why a divergence in it went unnoticed.
 */
export function haversineMetres(
	lat1: number,
	lng1: number,
	lat2: number,
	lng2: number
): number {
	const r = 6371000;
	const dLat = ((lat2 - lat1) * Math.PI) / 180;
	const dLng = ((lng2 - lng1) * Math.PI) / 180;
	const sinLat = Math.sin(dLat / 2);
	const sinLng = Math.sin(dLng / 2);
	const a =
		sinLat * sinLat +
		Math.cos((lat1 * Math.PI) / 180) *
			Math.cos((lat2 * Math.PI) / 180) *
			sinLng *
			sinLng;
	// Clamp before the arc. Rounding can push `a` a hair above 1 for a
	// near-antipodal pair, and then `Math.sqrt(1 - a)` is NaN — which propagates
	// silently through every consumer (moving time, splits, segment distances)
	// rather than throwing. The Dart twin clamps identically; an earlier pass
	// fixed only that side on the false belief that this one already did, which
	// left the pair divergent with the NaN moved here. Measured on
	// (-87.5, 0, 87.5, 180): unclamped NaN, clamped 20015086.796.
	const clamped = a > 1 ? 1 : a < 0 ? 0 : a;
	return r * 2 * Math.asin(Math.sqrt(clamped));
}
