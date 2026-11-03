import type { Climb, StripSample } from '#lib/routes/course_climbs.ts';

export interface StripGeometry {
	line: string;
	area: string;
	climbs: { x0: number; x1: number; climb: Climb }[];
}

/// Distance runs left to right over the full course (not over the sampled
/// span), so the strip's x for a distance is the same x the cursor and a
/// pointer scrub use. Elevation is scaled to the strip's own min..max with a
/// floor on the range, so a flat course reads flat instead of as noise
/// stretched to the full height.
export function stripGeometry(
	samples: readonly StripSample[],
	climbs: readonly Climb[],
	totalM: number,
	width: number,
	height: number,
	minRangeM = 20,
): StripGeometry {
	if (samples.length < 2 || !(totalM > 0) || !(width > 0) || !(height > 0)) {
		return { line: '', area: '', climbs: [] };
	}
	let lo = Infinity;
	let hi = -Infinity;
	for (const s of samples) {
		if (s.ele < lo) lo = s.ele;
		if (s.ele > hi) hi = s.ele;
	}
	const range = Math.max(hi - lo, minRangeM);
	const base = lo - (range - (hi - lo)) / 2;
	const x = (dM: number) => stripX(dM, totalM, width);
	const y = (ele: number) => round(height - ((ele - base) / range) * height);
	const pts = samples.map((s) => `${x(s.dM)},${y(s.ele)}`);
	const line = `M${pts.join(' L')}`;
	const area = `${line} L${x(samples[samples.length - 1].dM)},${height} L${x(samples[0].dM)},${height} Z`;
	return {
		line,
		area,
		climbs: climbs.map((climb) => ({ x0: x(climb.startM), x1: x(climb.endM), climb })),
	};
}

export function stripX(dM: number, totalM: number, width: number): number {
	if (!(totalM > 0)) return 0;
	return round(clamp01(dM / totalM) * width);
}

export function distanceAtStripOffset(offsetPx: number, widthPx: number, totalM: number): number {
	if (!(widthPx > 0) || !(totalM > 0) || !Number.isFinite(offsetPx)) return 0;
	return clamp01(offsetPx / widthPx) * totalM;
}

function clamp01(v: number): number {
	return Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : 0;
}

function round(v: number): number {
	return Math.round(v * 10) / 10;
}
