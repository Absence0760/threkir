// Pure pace-bucket / age-band helpers backing the NRC-style pace
// heatmap on the run map. TypeScript port of
// `apps/mobile_android/lib/widgets/pace_segments.dart` — keep them in
// lockstep so a run rendered on web and on mobile shows the same
// colours at the same points.

import type { TrackPoint } from '../types';
import { haversineMetres } from '../runs/run_stats';

export type ActivityKind = 'run' | 'walk' | 'cycle' | 'hike';

/// Slow → fast colour ramp, 6 buckets. Bucket count matches the
/// breakpoints array (5 breakpoints partition speed into 6 buckets).
export const PACE_RAMP: readonly string[] = [
	'#EF4444', // red — slowest
	'#F97316', // orange
	'#FBBF24', // amber
	'#A3E635', // lime
	'#10B981', // emerald
	'#22D3EE', // cyan — fastest
];

/// Three age bands (oldest → newest) applied as alpha on top of the
/// pace colour. The tail of the run fades out like a comet; the segment
/// nearest the runner is fully opaque.
export const AGE_ALPHAS: readonly number[] = [0.55, 0.8, 1.0];

/// Speed break-points (m/s), slow → fast. Four activities use pace
/// (min/km); cycling is displayed as speed but the buckets are
/// expressed in m/s so a single helper handles both. Values mirror
/// `_speedBreakpoints` in the Dart twin.
const SPEED_BREAKPOINTS: Record<ActivityKind, number[]> = {
	run: [2.2, 2.7, 3.2, 3.7, 4.4],
	walk: [1.0, 1.3, 1.6, 1.8, 2.2],
	cycle: [3.3, 5.0, 6.7, 8.3, 10.0],
	hike: [0.8, 1.1, 1.4, 1.7, 2.2],
};

/// Which pace bucket the given speed falls into. Bucket 0 is slowest,
/// `breakpoints.length` is fastest. Clamped at both ends.
export function paceBucketForSpeed(mps: number, activity: ActivityKind): number {
	const breaks = SPEED_BREAKPOINTS[activity];
	for (let i = 0; i < breaks.length; i++) {
		if (mps < breaks[i]) return i;
	}
	return breaks.length;
}

/// Which age band the segment at [segmentIndex] falls into, given
/// [segmentCount] segments. Index 0 = oldest, index 2 = newest. Short
/// tracks (≤ 1 segment) are treated as fully newest.
export function ageBandFor(segmentIndex: number, segmentCount: number): number {
	if (segmentCount <= 1) return 2;
	const f = segmentIndex / (segmentCount - 1);
	if (f < 1 / 3) return 0;
	if (f < 2 / 3) return 1;
	return 2;
}

function segmentSpeedMps(a: TrackPoint, b: TrackPoint): number | null {
	if (!a.ts || !b.ts) return null;
	const dtSec = (Date.parse(b.ts) - Date.parse(a.ts)) / 1000;
	if (!Number.isFinite(dtSec) || dtSec <= 0) return null;
	const d = haversineMetres(a.lat, a.lng, b.lat, b.lng);
	if (d <= 0) return null;
	return d / dtSec;
}

export interface PaceSegment {
	/// Polyline coordinates as [lng, lat] pairs (GeoJSON order).
	coords: [number, number][];
	/// rgba(...) string ready to pass to MapLibre `'line-color'`.
	color: string;
}

/// Build the list of polyline segments that make up the pace-coloured,
/// age-faded track. Each segment is assigned a `(paceBucket, ageBand)`
/// and consecutive segments sharing both are coalesced into a single
/// polyline so the map doesn't have to draw one feature per GPS fix.
///
/// Returns an empty list for tracks with fewer than two points. When
/// timestamps are missing for some segments, those buckets fall back to
/// 0 (slowest), matching the Dart twin. The caller is responsible for
/// using [hasTrackTimestamps] to decide whether the heatmap is
/// meaningful, or falling through to the single-gradient render path.
export function buildPaceSegments(track: TrackPoint[], activity: ActivityKind): PaceSegment[] {
	if (track.length < 2) return [];
	const segCount = track.length - 1;
	const paceBucket = new Array<number>(segCount);
	for (let i = 0; i < segCount; i++) {
		const mps = segmentSpeedMps(track[i], track[i + 1]);
		paceBucket[i] = mps === null ? 0 : paceBucketForSpeed(mps, activity);
	}

	const ageBand = new Array<number>(segCount);
	for (let i = 0; i < segCount; i++) ageBand[i] = ageBandFor(i, segCount);

	const out: PaceSegment[] = [];
	let runStart = 0;
	const emit = (firstSeg: number, lastSegExclusive: number) => {
		const coords: [number, number][] = [];
		for (let j = firstSeg; j <= lastSegExclusive; j++) {
			coords.push([track[j].lng, track[j].lat]);
		}
		out.push({ coords, color: rgbaFor(paceBucket[firstSeg], ageBand[firstSeg]) });
	};

	for (let i = 1; i < segCount; i++) {
		if (paceBucket[i] !== paceBucket[i - 1] || ageBand[i] !== ageBand[i - 1]) {
			emit(runStart, i);
			runStart = i;
		}
	}
	emit(runStart, segCount);
	return out;
}

/// True iff at least one consecutive pair of waypoints in [track]
/// carries usable timestamps (so a meaningful pace can be computed).
/// Cheap precondition check the caller can use to gate the heatmap
/// render path.
export function hasTrackTimestamps(track: TrackPoint[]): boolean {
	for (let i = 1; i < track.length; i++) {
		if (track[i - 1].ts && track[i].ts) return true;
	}
	return false;
}

function rgbaFor(bucket: number, ageBand: number): string {
	const hex = PACE_RAMP[Math.max(0, Math.min(PACE_RAMP.length - 1, bucket))];
	const alpha = AGE_ALPHAS[Math.max(0, Math.min(AGE_ALPHAS.length - 1, ageBand))];
	const r = parseInt(hex.slice(1, 3), 16);
	const g = parseInt(hex.slice(3, 5), 16);
	const b = parseInt(hex.slice(5, 7), 16);
	return `rgba(${r},${g},${b},${alpha})`;
}

/// Finished-run pace ramp, slow → fast. Sequential (one hue family, ordered
/// by lightness) rather than the live map's six-bucket traffic light, so a
/// steady run reads as one warm line instead of confetti. Kept in lockstep
/// with `paceGradientRamp` in `pace_segments.dart`.
export const PACE_GRADIENT_RAMP: readonly string[] = [
	'#FACC15', // yellow — slowest
	'#F97316', // orange
	'#DC2626', // red — fastest
];

/// Half-width of the centred window `smoothedSpeeds` averages over. One GPS
/// fix a second at ~3 m apart has metres of position error, which swings a
/// fix-to-fix speed by 30-100 %; 30 s of travel averages that out while
/// still showing a hill or a stoplight.
export const PACE_SMOOTHING_HALF_WINDOW_S = 15;

/// Number of distance bins a finished-run pace line is drawn in.
export const PACE_GRADIENT_BINS = 128;

function cumulativeMetres(track: TrackPoint[]): number[] {
	const cum = new Array<number>(track.length).fill(0);
	for (let i = 1; i < track.length; i++) {
		const a = track[i - 1];
		const b = track[i];
		cum[i] = cum[i - 1] + haversineMetres(a.lat, a.lng, b.lat, b.lng);
	}
	return cum;
}

/// Per-point speed (m/s) over a centred ±PACE_SMOOTHING_HALF_WINDOW_S window,
/// measured as along-track distance over elapsed time. Null where the point
/// has no timestamp or the window spans no time.
export function smoothedSpeeds(track: TrackPoint[]): (number | null)[] {
	const n = track.length;
	const out = new Array<number | null>(n).fill(null);
	if (n < 2) return out;
	const cum = cumulativeMetres(track);
	const secs = track.map((p) => {
		if (!p.ts) return null;
		const ms = Date.parse(p.ts);
		return Number.isFinite(ms) ? ms / 1000 : null;
	});
	let lo = 0;
	let hi = 0;
	for (let i = 0; i < n; i++) {
		const s = secs[i];
		if (s == null) continue;
		while (lo < i && (secs[lo] == null || (secs[lo] as number) < s - PACE_SMOOTHING_HALF_WINDOW_S)) {
			lo++;
		}
		if (hi < i) hi = i;
		while (
			hi + 1 < n &&
			secs[hi + 1] != null &&
			(secs[hi + 1] as number) <= s + PACE_SMOOTHING_HALF_WINDOW_S
		) {
			hi++;
		}
		const dt = (secs[hi] as number) - (secs[lo] as number);
		if (dt <= 0) continue;
		out[i] = (cum[hi] - cum[lo]) / dt;
	}
	return out;
}

/// One colour stop on a finished-run pace line: `fraction` is the position
/// along the track by distance (0..1), `t` the pace on the run's own scale
/// (0 = slowest, 1 = fastest).
export interface PaceStop {
	fraction: number;
	t: number;
}

/// Colour stops for a finished run's pace line, one per non-empty distance
/// bin. The domain is the run's own 5th-95th percentile of smoothed speed, so
/// a stop at a crossing or a GPS spike cannot stretch the scale for the rest
/// of the run. Empty when the track carries no usable timing.
export function paceGradientStops(track: TrackPoint[], bins = PACE_GRADIENT_BINS): PaceStop[] {
	const n = track.length;
	if (n < 2 || bins < 1) return [];
	const speeds = smoothedSpeeds(track);
	const known = speeds.filter((v): v is number => v != null).sort((a, b) => a - b);
	if (known.length === 0) return [];
	const lo = known[Math.floor((known.length - 1) * 0.05)];
	const hi = known[Math.floor((known.length - 1) * 0.95)];
	const span = hi - lo;

	const cum = cumulativeMetres(track);
	const total = cum[n - 1];
	if (total <= 0) return [];

	const sums = new Array<number>(bins).fill(0);
	const counts = new Array<number>(bins).fill(0);
	for (let i = 0; i < n; i++) {
		const v = speeds[i];
		if (v == null) continue;
		const t = span < 0.05 ? 0.5 : Math.max(0, Math.min(1, (v - lo) / span));
		const bin = Math.min(bins - 1, Math.floor((cum[i] / total) * bins));
		sums[bin] += t;
		counts[bin]++;
	}
	const out: PaceStop[] = [];
	for (let b = 0; b < bins; b++) {
		if (counts[b] > 0) out.push({ fraction: (b + 0.5) / bins, t: sums[b] / counts[b] });
	}
	return out;
}

/// The PACE_GRADIENT_RAMP colour at `t` (0 = slowest, 1 = fastest), as hex.
export function paceGradientColour(t: number): string {
	const c = Math.max(0, Math.min(1, t)) * (PACE_GRADIENT_RAMP.length - 1);
	const i = Math.min(Math.floor(c), PACE_GRADIENT_RAMP.length - 2);
	const f = c - i;
	const a = PACE_GRADIENT_RAMP[i];
	const b = PACE_GRADIENT_RAMP[i + 1];
	const ch = (hex: string, k: number) => parseInt(hex.slice(1 + 2 * k, 3 + 2 * k), 16);
	const mix = (k: number) => Math.round(ch(a, k) + (ch(b, k) - ch(a, k)) * f);
	return `#${[0, 1, 2].map((k) => mix(k).toString(16).padStart(2, '0')).join('')}`.toUpperCase();
}
