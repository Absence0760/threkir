// Seeded GPS runs over the real catalogue courses for the box timing rule
// (issue #1446, decisions § 2589): how often a run that did the course gets a
// time when it stops just past or just short of the finish, starts recording
// on the start line, records sparse fixes, loses GPS at the finish, or is a
// 50K. Not a test file itself, and not shipped: course_box_timing.test.ts
// imports it, and so can a script that scores the same runs with an older
// matcher bundle to compare.
//
// A run follows the course line from `startBehindM` behind the point where
// the line meets the start line to `stopPastM` past the point where it meets
// the finish line (negative: short of it), at a steady pace with ±10 % per
// fix, a fix every `everyS` seconds, and per-axis GPS error from a
// first-order Gauss-Markov process (`noiseM` standard deviation, correlated
// over 30 s, drawn from its stationary spread at the first fix).

import type { TrackPoint } from '../types';
import type { GlobalSegmentGeometry } from '../segments/segments';
import { hopM, mulberry32, offset, slice, type LatLng, type ParkCourse } from './course_run_fixture';

export const SIM_PARK_DIRS = [
	'scripts/parks/catalogue/us-va/pocahontas',
	'scripts/parks/catalogue/us-va/deep-run',
	'scripts/parks/catalogue/us-va/virginia-capital-trail',
] as const;

const NOISE_TAU_S = 30;
const T0 = Date.parse('2026-06-06T12:00:00Z');

export interface SimScenario {
	label: string;
	/** Metres behind the start line the recording begins; negative is past it. */
	startBehindM: number;
	/** Metres past the finish line the recording ends; negative is short of it. */
	stopPastM: number;
	speedMps: number;
	everyS: number;
	noiseM: number;
	/** A stretch with no fixes for this many seconds, starting `gapEndsShortM` before the finish line. */
	gapS?: number;
	gapEndsShortM?: number;
	/** The run stops at this share of the course instead (a run that gave up). */
	stopAtShare?: number;
	/** Seconds standing still at the end with the recorder running. */
	standS?: number;
	/** A short cut: the stretch between these shares of the course is skipped in a straight line. */
	cut?: [number, number];
}

export type Scorer = (track: TrackPoint[], geometry: GlobalSegmentGeometry) => { time_seconds: number } | null;

/** How far along `line` the point nearest `p` is, searching between fromM and toM. */
function alongM(line: readonly LatLng[], p: LatLng, fromM: number, toM: number): number {
	let best = Infinity;
	let at = fromM;
	let walked = 0;
	for (let i = 1; i < line.length; i++) {
		const a = line[i - 1];
		const b = line[i];
		const step = hopM(a, b);
		if (walked + step >= fromM && walked <= toM && step > 0) {
			for (let k = 0; k <= 20; k++) {
				const f = k / 20;
				const q = { lat: a.lat + f * (b.lat - a.lat), lng: a.lng + f * (b.lng - a.lng) };
				const d = hopM(q, p);
				const m = walked + f * step;
				if (d < best && m >= fromM && m <= toM) {
					best = d;
					at = m;
				}
			}
		}
		walked += step;
	}
	return at;
}

/** Where the course line meets its start and finish lines, metres along it. */
export function simLineSpan(course: ParkCourse): { startM: number; endM: number } {
	const total = course.lineM;
	return {
		startM: alongM(course.line, course.gates.start, 0, total / 2),
		endM: alongM(course.line, course.gates.end, total / 2, total),
	};
}

/** The path a scenario's runner takes over a course, start to stop. */
export function simPath(course: ParkCourse, s: SimScenario): LatLng[] {
	const line = course.line;
	const total = course.lineM;
	const { startM, endM } = simLineSpan(course);
	const from = startM - s.startBehindM;
	const to = s.stopAtShare !== undefined ? startM + s.stopAtShare * (endM - startM) : endM + s.stopPastM;
	const body = s.cut
		? [
				...slice(line, Math.max(0, from), startM + s.cut[0] * (endM - startM)),
				...slice(line, startM + s.cut[1] * (endM - startM), Math.min(total, to)),
			]
		: slice(line, Math.max(0, from), Math.min(total, to));
	if (from < 0) body.unshift(offset(line[0], course.gates.start.bearingDeg, from));
	if (to > total) body.push(offset(line[line.length - 1], course.gates.end.bearingDeg, to - total));
	return body;
}

/** One seeded run of a scenario over a course. */
export function simRun(course: ParkCourse, s: SimScenario, seed: number): TrackPoint[] {
	const path = simPath(course, s);
	const cum = [0];
	for (let i = 1; i < path.length; i++) cum.push(cum[i - 1] + hopM(path[i - 1], path[i]));
	const total = cum[cum.length - 1];
	const gapFrom = s.gapS !== undefined ? total - s.stopPastM - (s.gapEndsShortM ?? 0) - s.speedMps * s.gapS : null;
	const rnd = mulberry32(seed);
	const gauss = () => {
		let u = 0;
		while (u === 0) u = rnd();
		return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * rnd());
	};
	const rho = Math.exp(-s.everyS / NOISE_TAU_S);
	const k = Math.sqrt(1 - rho * rho);
	let ex = gauss() * s.noiseM;
	let ey = gauss() * s.noiseM;
	const out: TrackPoint[] = [];
	let seg = 1;
	let d = 0;
	let t = 0;
	const at = (dist: number): LatLng => {
		while (seg < path.length - 1 && cum[seg] < dist) seg++;
		const a = path[seg - 1];
		const b = path[seg];
		const span = cum[seg] - cum[seg - 1];
		const f = span > 0 ? Math.min(1, (dist - cum[seg - 1]) / span) : 0;
		return { lat: a.lat + f * (b.lat - a.lat), lng: a.lng + f * (b.lng - a.lng) };
	};
	const push = (p: LatLng) => {
		const q = offset(offset(p, 90, ex), 0, ey);
		out.push({ lat: q.lat, lng: q.lng, ts: new Date(T0 + t * 1000).toISOString() });
	};
	for (;;) {
		const gapped = gapFrom !== null && d > gapFrom && d < gapFrom + s.speedMps * (s.gapS as number);
		if (!gapped) push(at(d));
		if (d >= total) break;
		t += s.everyS;
		d = Math.min(total, d + s.speedMps * s.everyS * (0.9 + 0.2 * rnd()));
		ex = rho * ex + k * gauss() * s.noiseM;
		ey = rho * ey + k * gauss() * s.noiseM;
	}
	const end = path[path.length - 1];
	for (let w = s.everyS; w <= (s.standS ?? 0); w += s.everyS) {
		t += s.everyS;
		ex = rho * ex + k * gauss() * s.noiseM;
		ey = rho * ey + k * gauss() * s.noiseM;
		push(end);
	}
	return out;
}

export interface SimRate {
	timed: number;
	trials: number;
}

/** How many of `trials` seeded runs of the scenario over the course the scorer times. */
export function simTimedRate(course: ParkCourse, s: SimScenario, trials: number, score: Scorer, seed = 1): SimRate {
	let timed = 0;
	for (let i = 0; i < trials; i++) {
		if (score(simRun(course, s, seed * 7919 + i), course.geometry) !== null) timed++;
	}
	return { timed, trials };
}

/** The scenarios of issue #1446's table, at a 3 m drifting GPS error. */
export function simScenarios(): SimScenario[] {
	const base = { startBehindM: 3, stopPastM: 5, speedMps: 3, everyS: 1, noiseM: 3 };
	return [
		{ ...base, label: 'stop 5 m past the finish' },
		{ ...base, stopPastM: 1, label: 'stop 1 m past the finish' },
		{ ...base, stopPastM: -3, label: 'stop 3 m short of the finish line' },
		{ ...base, stopPastM: -3, standS: 10, label: 'stop 3 m short, stand 10 s' },
		{ ...base, startBehindM: 0.5, label: 'start recording 0.5 m behind the start line' },
		{ ...base, startBehindM: 0, label: 'start recording on the start line' },
		{ ...base, everyS: 5, label: 'a fix every 5 s' },
		{ ...base, everyS: 15, label: 'a fix every 15 s' },
		{ ...base, stopPastM: 15, gapS: 90, gapEndsShortM: -5, label: '90 s GPS gap across the finish' },
		{ ...base, stopAtShare: 0.5, label: 'stop halfway' },
		{ ...base, cut: [0.4, 0.6], label: 'cut the middle fifth' },
		{ ...base, cut: [0.1, 0.3], label: 'cut a fifth near the start' },
		{ ...base, cut: [0.7, 0.9], label: 'cut a fifth near the finish' },
	];
}
