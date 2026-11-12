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
// unmarked on a recorded run: the foot only moves on a new low, so the grade
// is read from the false flat's start.
//
// A planned route or race course is read by a second rule (`'planned'`,
// decisions § 2294). Its heights come from a terrain model or the course's
// own GPX, without the metre-a-second wander of a watch's altitude that the
// 2 % floor rejects, and road-race climbs gain 20-30 m at 1-1.5 %: under the
// watch rule Philadelphia's three marked hills read as no climbs at all.

import type { FlyoverPath } from './flyover_path';
import { ELEVATION_GAIN_MIN_DELTA_M } from './route_simplify';

/// Gain above the last low point that opens a climb (`CLIMB_START_GAIN_M`).
export const CLIMB_START_GAIN_M = 20;

/// Average grade from the foot that the opening gain must also clear
/// (`CLIMB_MIN_GRADE_PCT`): 20 m over 4 km is a false flat, not an ascent.
export const CLIMB_MIN_GRADE_PCT = 2;

/// A planned series' climb opens once the course has risen at least
/// `PLANNED_CLIMB_MIN_GAIN_M` within the last `PLANNED_CLIMB_WINDOW_M`, an
/// average of at least `PLANNED_CLIMB_MIN_GRADE_PCT` (20 m in 2 km is 1 %).
/// Measured over that trailing window rather than from the last low, so a
/// climb after kilometres of gentle rise still opens.
export const PLANNED_CLIMB_MIN_GAIN_M = CLIMB_START_GAIN_M;
export const PLANNED_CLIMB_MIN_GRADE_PCT = 1;
export const PLANNED_CLIMB_WINDOW_M = (PLANNED_CLIMB_MIN_GAIN_M / PLANNED_CLIMB_MIN_GRADE_PCT) * 100;

/// Where the heights came from: a recorded run's altitude (`'recorded'`, the
/// watch rule) or a route or course drawn on a terrain model (`'planned'`).
export type ClimbSource = 'planned' | 'recorded';

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

interface Span {
	foot: number;
	crest: number;
}

/// The watch's `ClimbDetector`: opens 20 m above the last low at 2 % from it.
function recordedSpans(samples: EleSample[], endDrop: number): Span[] {
	const spans: Span[] = [];
	let low = 0;
	let high = 0;
	let climbing = false;

	for (let i = 1; i < samples.length; i++) {
		const s = samples[i];
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
	// The detector opens a climb exactly as the watch does; only then is the
	// foot moved up a flat approach at the low height, so the span starts
	// where the road starts rising without changing which climbs exist.
	return spans.map(({ foot, crest }) => {
		let f = foot;
		while (f + 1 < crest && samples[f + 1].ele <= samples[f].ele) f++;
		return { foot: f, crest };
	});
}

/// The foot of a planned climb: of the points since the last close that sit
/// at least the opening gain below the crest, the lowest once the floor grade
/// is taken out of the profile. A stretch rising slower than the floor then
/// counts as approach, so the foot sits where the climb proper starts rather
/// than at the start of the false flat before it, and the climb still gains
/// at least the opening gain. Its gain is measured from that foot, so it can
/// be less than lowest-to-crest when the approach rose slower than 1 %.
function plannedFoot(samples: EleSample[], from: number, crest: number): number {
	const k = PLANNED_CLIMB_MIN_GRADE_PCT / 100;
	const ceiling = samples[crest].ele - PLANNED_CLIMB_MIN_GAIN_M;
	let foot = -1;
	let best = Infinity;
	for (let j = from; j < crest; j++) {
		const s = samples[j];
		// A point level with the crest in distance would make a climb with no
		// length, a gain at 0 %.
		if (s.ele > ceiling || s.dM >= samples[crest].dM) continue;
		const v = s.ele - k * s.dM;
		if (v < best) {
			best = v;
			foot = j;
		}
	}
	return foot;
}

/// A planned series: opens when the lowest point of the trailing window is
/// the opening gain below the current one, closes on the same drop as the
/// watch. The window minimum is a monotonic deque, so a 10 000-point GPX is
/// one pass.
function plannedSpans(samples: EleSample[], endDrop: number): Span[] {
	const spans: Span[] = [];
	let from = 0;
	let high = 0;
	let climbing = false;
	const window: number[] = [0];

	for (let i = 1; i < samples.length; i++) {
		const s = samples[i];
		if (climbing) {
			if (s.ele > samples[high].ele) high = i;
			if (samples[high].ele - s.ele >= endDrop) {
				spans.push({ foot: plannedFoot(samples, from, high), crest: high });
				climbing = false;
				from = i;
				window.length = 0;
				window.push(i);
			}
			continue;
		}
		while (window.length > 0 && samples[window[window.length - 1]].ele >= s.ele) window.pop();
		window.push(i);
		while (samples[window[0]].dM < s.dM - PLANNED_CLIMB_WINDOW_M) window.shift();
		if (s.ele - samples[window[0]].ele >= PLANNED_CLIMB_MIN_GAIN_M) {
			climbing = true;
			high = i;
		}
	}
	if (climbing) spans.push({ foot: plannedFoot(samples, from, high), crest: high });
	return spans.filter((sp) => sp.foot >= 0);
}

export function detectClimbs(
	path: FlyoverPath,
	opts: {
		source: ClimbSource;
		names?: readonly { dM: number; name: string }[];
		noiseBandM?: number;
	},
): Climb[] {
	const all = elevationSamples(path);
	// A point behind the one before it (a duplicated or reordered fix) is
	// dropped, so distance only moves forward.
	const samples: EleSample[] = [];
	for (const s of all) {
		if (samples.length === 0 || s.dM >= samples[samples.length - 1].dM) samples.push(s);
	}
	if (samples.length < 2) return [];
	const endDrop = climbEndDropM(opts.noiseBandM ?? ELEVATION_GAIN_MIN_DELTA_M);
	const spans = opts.source === 'planned' ? plannedSpans(samples, endDrop) : recordedSpans(samples, endDrop);

	const names = [...(opts.names ?? [])]
		.filter((n) => Number.isFinite(n.dM))
		.sort((a, b) => a.dM - b.dM);
	return spans.map(({ foot: f, crest: c }) => {
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

/// Highest less lowest height along the path, or null when it carries no
/// elevation worth reading (the same rule the climbs and the strip use).
export function courseReliefM(path: FlyoverPath): number | null {
	const samples = elevationSamples(path);
	if (samples.length < 2) return null;
	let lo = Infinity;
	let hi = -Infinity;
	for (const s of samples) {
		if (s.ele < lo) lo = s.ele;
		if (s.ele > hi) hi = s.ele;
	}
	return hi - lo;
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
