// Shaping for the run-detail elevation chart: distance-window smoothing and
// the y-axis domain. Twin of `apps/mobile_android/lib/elevation_profile.dart`
// — keep them in lockstep so one run draws the same profile on both.

import type { TrackPoint } from '../types';
import { haversineMetres } from './run_stats';

/// Half-width of the along-track window `smoothElevation` averages over.
/// Phone GPS altitude wanders by metres between fixes a second apart; an
/// 80 m window keeps a real climb and drops the per-fix sawtooth.
export const ELEVATION_SMOOTHING_HALF_WINDOW_M = 40;

/// Smallest vertical span the chart will draw. Stretching 3 m of jitter over
/// the full chart height made a flat run look mountainous.
export const ELEVATION_MIN_SPAN_M = 30;

/// Distance from the start to each point of `track`, in metres.
export function cumulativeMetres(track: TrackPoint[]): number[] {
	const out = new Array<number>(track.length).fill(0);
	for (let i = 1; i < track.length; i++) {
		const a = track[i - 1];
		const b = track[i];
		out[i] = out[i - 1] + haversineMetres(a.lat, a.lng, b.lat, b.lng);
	}
	return out;
}

/// Centred moving average of `series` over the points within ±h of each
/// point's along-track distance, where h is `halfWindowM` shrunk near either
/// end so the window stays symmetric. A one-sided window at the ends would
/// drag the first and last values toward the middle; a symmetric one leaves
/// a straight climb exactly as recorded, ends included. Same length as the
/// input, so a hovered index still maps back to the same track point.
export function smoothElevation(
	series: number[],
	cumulativeM: number[],
	halfWindowM: number = ELEVATION_SMOOTHING_HALF_WINDOW_M,
): number[] {
	const n = series.length;
	if (n !== cumulativeM.length) throw new Error('series and cumulativeM must match');
	const prefix = new Array<number>(n + 1).fill(0);
	for (let i = 0; i < n; i++) prefix[i + 1] = prefix[i] + series[i];
	const firstAtLeast = (d: number) => {
		let lo = 0;
		let hi = n - 1;
		while (lo < hi) {
			const mid = (lo + hi) >> 1;
			if (cumulativeM[mid] < d) lo = mid + 1;
			else hi = mid;
		}
		return lo;
	};
	const lastAtMost = (d: number) => {
		let lo = 0;
		let hi = n - 1;
		while (lo < hi) {
			const mid = (lo + hi + 1) >> 1;
			if (cumulativeM[mid] > d) hi = mid - 1;
			else lo = mid;
		}
		return lo;
	};
	const total = n > 0 ? cumulativeM[n - 1] : 0;
	const out = new Array<number>(n);
	for (let i = 0; i < n; i++) {
		const h = Math.min(halfWindowM, cumulativeM[i] - cumulativeM[0], total - cumulativeM[i]);
		const lo = Math.min(i, firstAtLeast(cumulativeM[i] - h));
		const hi = Math.max(i, lastAtMost(cumulativeM[i] + h));
		out[i] = (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1);
	}
	return out;
}

/// The y-axis range for a profile spanning `min`..`max` metres: at least
/// ELEVATION_MIN_SPAN_M tall, centred on the data, plus 10 % headroom on
/// each side so the line never touches the frame.
export function elevationDomain(min: number, max: number): { lo: number; hi: number } {
	let a = Math.min(min, max);
	let b = Math.max(min, max);
	const span = b - a;
	if (span < ELEVATION_MIN_SPAN_M) {
		const extra = (ELEVATION_MIN_SPAN_M - span) / 2;
		a -= extra;
		b += extra;
	}
	const pad = (b - a) * 0.1;
	return { lo: a - pad, hi: b + pad };
}
