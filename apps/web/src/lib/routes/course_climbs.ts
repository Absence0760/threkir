// The climbs a course preview marks, and the elevation strip it draws under
// the flight. A climb's gain is net height, foot to crest, over the series it
// is handed: the definition a split's elevation in the run splits table uses
// (end minus start) and the watch's `ActiveClimb.gain_m`. It is not total
// ascent (`computeElevationGain`), which counts every re-climbed dip.
//
// The segmentation is the watch firmware's `watch_core::climb::ClimbDetector`
// (decisions § 359) run over a whole course instead of a live stream, with
// the same thresholds, so a hill is one climb on the wrist and in the preview.
// Like the watch, a short steep ramp at the end of a long false flat stays
// unmarked: the foot only moves on a new low, so the grade is read from the
// false flat's start.

import type { FlyoverPath } from './flyover_path';
import { ELEVATION_GAIN_MIN_DELTA_M } from './route_simplify';

/// Gain above the last low point that opens a climb (`CLIMB_START_GAIN_M`).
export const CLIMB_START_GAIN_M = 20;

/// Average grade from the foot that the opening gain must also clear
/// (`CLIMB_MIN_GRADE_PCT`): 20 m over 4 km is a false flat, not an ascent.
export const CLIMB_MIN_GRADE_PCT = 2;

/// Loss below the high point that ends a climb (`CLIMB_END_DROP_M`). A dip
/// shallower than this is inside the climb, which is what merges two ramps
/// separated by a saddle into the one climb a runner experiences.
export const CLIMB_END_DROP_M = 10;

/// The drop that ends a climb over a series whose noise band is `noiseBandM`.
/// The band is the one the series' total ascent is gated on (`runAltitude`'s
/// `minDeltaM`: 3 m for a route or a barometer, 10 m for phone GPS altitude).
/// A drop must clear two bands to be descent, or a single GPS wobble halfway
/// up a hill splits it in two.
export function climbEndDropM(noiseBandM: number): number {
	return Number.isFinite(noiseBandM) ? Math.max(CLIMB_END_DROP_M, 2 * noiseBandM) : CLIMB_END_DROP_M;
}

export interface Climb {
	startM: number;
	endM: number;
	/** Net metres from the foot to the crest, rounded as the splits table rounds. */
	gainM: number;
	avgGradePct: number;
	name: string | null;
}

export interface StripSample {
	dM: number;
	ele: number;
}

interface EleSample {
	dM: number;
	ele: number;
}

/// The path's elevation samples, or [] when it carries none worth reading.
/// Fewer than two distinct heights is the roadbook's "no elevation" rule
/// (`roadbook.ts` `hasElevation`): it rejects the all-zero series
/// `fetchElevations` returns when the lookup was refused or failed.
function elevationSamples(path: FlyoverPath): EleSample[] {
	const out: EleSample[] = [];
	const distinct = new Set<number>();
	for (let i = 0; i < path.points.length; i++) {
		const ele = path.points[i].ele;
		const dM = path.cumM[i];
		if (ele == null || !Number.isFinite(ele) || !Number.isFinite(dM)) continue;
		out.push({ dM, ele });
		distinct.add(ele);
	}
	return distinct.size >= 2 ? out : [];
}

function gradePct(riseM: number, runM: number): number {
	return runM > 0 ? (riseM / runM) * 100 : 0;
}

export function detectClimbs(
	path: FlyoverPath,
	opts?: { names?: readonly { dM: number; name: string }[]; noiseBandM?: number },
): Climb[] {
	const samples = elevationSamples(path);
	if (samples.length < 2) return [];
	const endDrop = climbEndDropM(opts?.noiseBandM ?? ELEVATION_GAIN_MIN_DELTA_M);

	const spans: { foot: number; crest: number }[] = [];
	let low = 0;
	let high = 0;
	let climbing = false;
	let lastDM = samples[0].dM;

	for (let i = 1; i < samples.length; i++) {
		const s = samples[i];
		if (s.dM < lastDM) continue;
		lastDM = s.dM;
		if (s.ele > samples[high].ele) high = i;
		if (climbing) {
			if (samples[high].ele - s.ele >= endDrop) {
				spans.push({ foot: low, crest: high });
				climbing = false;
				low = i;
				high = i;
			}
			continue;
		}
		if (s.ele < samples[low].ele) {
			low = i;
			high = i;
			continue;
		}
		const gain = s.ele - samples[low].ele;
		if (gain >= CLIMB_START_GAIN_M && gradePct(gain, s.dM - samples[low].dM) >= CLIMB_MIN_GRADE_PCT) {
			climbing = true;
		}
	}
	if (climbing) spans.push({ foot: low, crest: high });

	const names = [...(opts?.names ?? [])]
		.filter((n) => Number.isFinite(n.dM))
		.sort((a, b) => a.dM - b.dM);
	return spans.map(({ foot: f, crest: c }) => {
		// The detector opens a climb exactly as the watch does; only then is the
		// foot moved up a flat approach at the low height, so the span starts
		// where the road starts rising without changing which climbs exist.
		while (f + 1 < c && samples[f + 1].ele <= samples[f].ele) f++;
		const foot = samples[f];
		const crest = samples[c];
		const rise = crest.ele - foot.ele;
		return {
			startM: foot.dM,
			endM: crest.dM,
			gainM: Math.round(rise),
			avgGradePct: gradePct(rise, crest.dM - foot.dM),
			name: names.find((n) => n.dM >= foot.dM && n.dM <= crest.dM)?.name ?? null,
		};
	});
}

/// `samples` heights at even distances from the start to the finish of the
/// path, interpolated linearly in distance between its own elevation samples.
/// A point without one is skipped, not read as 0 m, and a gap before the first
/// or after the last reading carries the nearest one — the same carry-across
/// `elevationSeries` applies, so the strip spans the whole flight.
export function elevationStrip(path: FlyoverPath, samples: number): StripSample[] {
	const known = elevationSamples(path);
	const n = Math.floor(samples);
	const total = path.totalM;
	if (known.length < 2 || !(n >= 2) || !(total > 0)) return [];

	const out: StripSample[] = [];
	let k = 0;
	for (let i = 0; i < n; i++) {
		const dM = (total * i) / (n - 1);
		while (k < known.length - 2 && known[k + 1].dM < dM) k++;
		const a = known[k];
		const b = known[k + 1];
		const f = b.dM > a.dM ? Math.min(1, Math.max(0, (dM - a.dM) / (b.dM - a.dM))) : 0;
		out.push({ dM, ele: a.ele + f * (b.ele - a.ele) });
	}
	return out;
}
