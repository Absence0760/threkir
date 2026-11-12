// The stretch of a run a tap on the run-detail map selects: the track within
// ±SEGMENT_RADIUS_M of cumulative distance around the tapped point, with its
// distance, time, pace, heart rate and climb. Mirrors
// apps/mobile_android/lib/widgets/track_segment.dart — keep both in lockstep so
// the same tap on the same run reads the same on both platforms.

import { haversineMetres } from '../routes/nearest_track_point';
import type { TrackPoint } from '../types';

export interface SelectedSegment {
	startIdx: number;
	endIdx: number;
	clickIdx: number;
	/// Cumulative distance along the drawn line where the stretch starts and
	/// ends, so the card can say which part of the run it measures.
	start_m: number;
	end_m: number;
	distance_m: number;
	duration_s: number | null;
	avg_pace_sec_per_km: number | null;
	avg_bpm: number | null;
	ele_gain_m: number;
	ele_loss_m: number;
	mid: TrackPoint;
}

export const SEGMENT_RADIUS_M = 150;

/** Cumulative metres from the first `[lng, lat]` to each one. */
export function buildCumulative(coords: [number, number][]): number[] {
	const out: number[] = new Array(coords.length).fill(0);
	for (let i = 1; i < coords.length; i++) {
		out[i] = out[i - 1] + haversineMetres(coords[i - 1], coords[i]);
	}
	return out;
}

/**
 * The segment centred on `clickIdx`, expanded outwards to ±SEGMENT_RADIUS_M of
 * `cumulativeM`. Null for a track under two points or a cumulative table that
 * does not index it.
 */
export function buildSegment(
	track: TrackPoint[],
	cumulativeM: number[],
	clickIdx: number,
): SelectedSegment | null {
	if (track.length < 2 || cumulativeM.length !== track.length) return null;
	const target = cumulativeM[clickIdx];
	let startIdx = clickIdx;
	while (startIdx > 0 && cumulativeM[startIdx - 1] >= target - SEGMENT_RADIUS_M) startIdx--;
	let endIdx = clickIdx;
	while (endIdx < cumulativeM.length - 1 && cumulativeM[endIdx + 1] <= target + SEGMENT_RADIUS_M)
		endIdx++;
	if (startIdx === endIdx) {
		// Edge of the track — widen by one neighbour so we have a real
		// segment rather than a single-point degenerate.
		if (endIdx < cumulativeM.length - 1) endIdx++;
		else if (startIdx > 0) startIdx--;
	}

	const start_m = cumulativeM[startIdx];
	const end_m = cumulativeM[endIdx];
	const distance_m = end_m - start_m;

	const startTs = track[startIdx]?.ts;
	const endTs = track[endIdx]?.ts;
	let duration_s: number | null = null;
	let avg_pace_sec_per_km: number | null = null;
	if (startTs && endTs) {
		const dt = (Date.parse(endTs) - Date.parse(startTs)) / 1000;
		if (Number.isFinite(dt) && dt > 0) {
			duration_s = Math.round(dt);
			if (distance_m > 10) {
				avg_pace_sec_per_km = Math.round(dt / (distance_m / 1000));
			}
		}
	}

	let bpmSum = 0;
	let bpmCount = 0;
	let eleGain = 0;
	let eleLoss = 0;
	for (let i = startIdx; i <= endIdx; i++) {
		const b = track[i]?.bpm;
		if (typeof b === 'number' && b >= 30 && b <= 230) {
			bpmSum += b;
			bpmCount++;
		}
		if (i > startIdx) {
			const prev = track[i - 1]?.ele;
			const cur = track[i]?.ele;
			if (typeof prev === 'number' && typeof cur === 'number') {
				const delta = cur - prev;
				if (delta > 0) eleGain += delta;
				else eleLoss += -delta;
			}
		}
	}

	return {
		startIdx,
		endIdx,
		clickIdx,
		start_m,
		end_m,
		distance_m,
		duration_s,
		avg_pace_sec_per_km,
		avg_bpm: bpmCount > 0 ? Math.round(bpmSum / bpmCount) : null,
		ele_gain_m: Math.round(eleGain),
		ele_loss_m: Math.round(eleLoss),
		mid: track[clickIdx],
	};
}
