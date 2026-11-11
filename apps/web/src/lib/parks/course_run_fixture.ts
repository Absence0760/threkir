// Synthetic GPS runs over the real Pocahontas park courses (issue #1342 step
// 5c), and the shared case table they make: fixtures/park_course_runs.json.
// Not a test file itself, and not shipped: tests and
// scripts/gen_park_course_runs.mjs import it.
//
// The generator is pure and seeded. From a course line it lays out what a
// phone records on the day: a minute standing in the lot waiting for a fix, a
// walk to the start, the course at a steady pace, a cool-down past the finish
// and a walk off. Fixes are 1 Hz, rounded to 1e-6 degrees, with GPS error
// from a first-order Gauss-Markov process (about 5 m RMS, correlated over
// ~40 s, as a phone's filtered fix is) plus a little white jitter. A canopy
// window thins the fixes and scales the error up, and a hold is a stop with
// the recorder still running.
//
// The lines a course is timed by are the ones the database gives it: derived
// here as the `global_segments_set_gates` trigger derives them (migration
// 20271122002402 over 20271116002390's `private.course_end_bearing`), or the
// manifest's curated line where it has one (decisions § 2424). The pgTAP test
// park_course_boards_test.sql loads the catalogue and checks the database's
// lines against these, so a drift in either is caught.

import type { TrackPoint } from '../types';
import { GATE_EARTH_RADIUS_M, GATE_HALF_WIDTH_SEGMENT_M, type Gate } from '../geo/gate_crossing';
import {
	computeGlobalSegmentEfforts,
	type GlobalSegmentEffortResult,
	type GlobalSegmentGeometry,
} from '../segments/segments';

export const PARK_DIR = 'scripts/parks/catalogue/us-va/pocahontas';
export const FIXTURE_FILE = 'fixtures/park_course_runs.json';

/** Every case's first fix, a Saturday morning in the park (13:00 UTC is 08:00 EST). */
export const BASE_TIME = '2026-11-07T13:00:00.000Z';

/** The GPS error a line crossing can carry at each end, for the elapsed-time tolerance. */
export const LINE_ERROR_M = 8;

export interface LatLng {
	lat: number;
	lng: number;
}

interface CuratedGate {
	lat: number;
	lng: number;
	bearing_deg: number;
	half_width_m: number;
}

interface ManifestCourse {
	slug: string;
	geojson: string;
	distance_m: number;
	checkpoints: LatLng[];
	laps?: number;
	lap_m?: number;
	lead_in_m?: number;
	start_line_from_lead_in_start_m?: number;
	start_gate?: CuratedGate;
	end_gate?: CuratedGate;
}

export interface ParkCourse {
	slug: string;
	geojson: string;
	distanceM: number;
	laps: number;
	checkpoints: LatLng[];
	line: LatLng[];
	lineM: number;
	/** Metres from the start line to where the lead-in meets the loop (race courses). */
	leadM: number;
	gates: { start: Gate; end: Gate };
	gateSources: { start: 'derived' | 'curator'; end: 'derived' | 'curator' };
	geometry: GlobalSegmentGeometry;
}

// ─────────────────────────── geometry ───────────────────────────

const rad = (d: number) => (d * Math.PI) / 180;

export function hopM(a: LatLng, b: LatLng): number {
	const dLat = rad(b.lat - a.lat);
	const dLng = rad(b.lng - a.lng);
	const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
	return 2 * GATE_EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

export function lengthM(pts: readonly LatLng[]): number {
	let t = 0;
	for (let i = 1; i < pts.length; i++) t += hopM(pts[i - 1], pts[i]);
	return t;
}

/** The polyline between fromM and toM metres along it, cut ends interpolated; reversed when fromM > toM. */
export function slice(pts: readonly LatLng[], fromM: number, toM: number): LatLng[] {
	if (fromM > toM) return slice(pts, toM, fromM).reverse();
	const out: LatLng[] = [];
	let walked = 0;
	for (let i = 1; i < pts.length; i++) {
		const a = pts[i - 1];
		const b = pts[i];
		const step = hopM(a, b);
		const at = (m: number) => {
			const t = step === 0 ? 0 : (m - walked) / step;
			return { lat: a.lat + t * (b.lat - a.lat), lng: a.lng + t * (b.lng - a.lng) };
		};
		if (out.length === 0 && walked + step >= fromM) out.push(at(fromM));
		if (walked + step >= toM) {
			out.push(at(toM));
			return out;
		}
		if (out.length > 0) out.push(b);
		walked += step;
	}
	return out;
}

/** The point distM metres from p on bearingDeg (a local plane, exact enough at these spans). */
export function offset(p: LatLng, bearingDeg: number, distM: number): LatLng {
	const x = distM * Math.sin(rad(bearingDeg));
	const y = distM * Math.cos(rad(bearingDeg));
	return {
		lat: p.lat + (y / GATE_EARTH_RADIUS_M) * (180 / Math.PI),
		lng: p.lng + (x / (GATE_EARTH_RADIUS_M * Math.cos(rad(p.lat)))) * (180 / Math.PI),
	};
}

export function planeXY(lat0: number, lng0: number, lat: number, lng: number): { x: number; y: number } {
	let dl = lng - lng0;
	if (dl >= 180) dl -= 360;
	else if (dl < -180) dl += 360;
	return {
		x: rad(dl) * GATE_EARTH_RADIUS_M * Math.cos(rad(lat0)),
		y: rad(lat - lat0) * GATE_EARTH_RADIUS_M,
	};
}

export function bearingOf(x: number, y: number): number {
	const b = ((((Math.atan2(x, y) * 180) / Math.PI + 360) % 360) + 360) % 360;
	return b >= 360 ? b - 360 : b;
}

/** `private.course_end_bearing`: the first point facing 25 m along, or the last facing from 25 m before. */
export function courseEndBearing(geom: readonly LatLng[], finish: boolean): number | null {
	const along = 25;
	const min = 10;
	const n = geom.length;
	if (n < 2) return null;
	const o = geom[finish ? n - 1 : 0];
	let px = 0;
	let py = 0;
	let tx = 0;
	let ty = 0;
	let acc = 0;
	for (let i = 1; i <= n - 1; i++) {
		const p = geom[finish ? n - 1 - i : i];
		const { x: cx, y: cy } = planeXY(o.lat, o.lng, p.lat, p.lng);
		const d = Math.sqrt((cx - px) ** 2 + (cy - py) ** 2);
		if (d > 0) {
			if (acc + d >= along) {
				const f = (along - acc) / d;
				tx = px + f * (cx - px);
				ty = py + f * (cy - py);
				acc = along;
				break;
			}
			acc += d;
			tx = cx;
			ty = cy;
		}
		px = cx;
		py = cy;
	}
	if (acc < min) return null;
	return finish ? bearingOf(-tx, -ty) : bearingOf(tx, ty);
}

/** The lines the trigger derives from a polyline, half-width GATE_HALF_WIDTH_SEGMENT_M. */
export function derivedGates(line: readonly LatLng[]): { start: Gate; end: Gate } {
	const sb = courseEndBearing(line, false);
	const eb = courseEndBearing(line, true);
	if (sb === null || eb === null) throw new Error('a course line too short to derive its lines');
	const first = line[0];
	const last = line[line.length - 1];
	return {
		start: { lat: first.lat, lng: first.lng, bearingDeg: sb, halfWidthM: GATE_HALF_WIDTH_SEGMENT_M },
		end: { lat: last.lat, lng: last.lng, bearingDeg: eb, halfWidthM: GATE_HALF_WIDTH_SEGMENT_M },
	};
}

function asGate(g: CuratedGate): Gate {
	return { lat: g.lat, lng: g.lng, bearingDeg: g.bearing_deg, halfWidthM: g.half_width_m };
}

// ─────────────────────────── the catalogue ───────────────────────────

/** Reads a file by its path from the repo root. */
export type RepoReader = (path: string) => string;

export function loadCourses(read: RepoReader): ParkCourse[] {
	const manifest = JSON.parse(read(`${PARK_DIR}/manifest.json`)) as {
		courses: ManifestCourse[];
		race_courses: ManifestCourse[];
	};
	return [...manifest.courses, ...manifest.race_courses].map((c) => {
		const gj = JSON.parse(read(`${PARK_DIR}/${c.geojson}`));
		const feature = gj.features.find((f: { geometry?: { type?: string } }) => f.geometry?.type === 'LineString');
		const line: LatLng[] = feature.geometry.coordinates.map((p: number[]) => ({ lat: p[1], lng: p[0] }));
		const derived = derivedGates(line);
		const gates = {
			start: c.start_gate ? asGate(c.start_gate) : derived.start,
			end: c.end_gate ? asGate(c.end_gate) : derived.end,
		};
		const leadM =
			c.lead_in_m !== undefined && c.start_line_from_lead_in_start_m !== undefined
				? c.lead_in_m - c.start_line_from_lead_in_start_m
				: 0;
		return {
			slug: c.slug,
			geojson: `${PARK_DIR}/${c.geojson}`,
			distanceM: c.distance_m,
			laps: c.laps ?? 1,
			checkpoints: c.checkpoints,
			line,
			lineM: lengthM(line),
			leadM,
			gates,
			gateSources: { start: c.start_gate ? 'curator' : 'derived', end: c.end_gate ? 'curator' : 'derived' },
			geometry: {
				points: line,
				distance_m: c.distance_m,
				checkpoints: c.checkpoints,
				startGate: gates.start,
				endGate: gates.end,
			},
		};
	});
}

// ─────────────────────────── the generator ───────────────────────────

export function mulberry32(seed: number): () => number {
	let a = seed >>> 0;
	return () => {
		a = (a + 0x6d2b79f5) >>> 0;
		let t = a;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

function gaussian(rnd: () => number): number {
	let u = 0;
	while (u === 0) u = rnd();
	return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * rnd());
}

/** Per-axis standard deviation of the correlated GPS error, metres (radial RMS about 5 m). */
export const NOISE_SIGMA_M = 3.5;
/** Correlation time of the GPS error, seconds. */
export const NOISE_TAU_S = 40;
/** Per-axis white jitter on every fix, metres. */
export const NOISE_WHITE_M = 0.3;

export type Step =
	/** Moving along `path` at `speedMps`; `mark` names its first instant, `endMark` its last. */
	| { kind: 'move'; path: LatLng[]; speedMps: number; mark?: string; endMark?: string }
	/** Standing still for `seconds` with the recorder running. */
	| { kind: 'hold'; seconds: number; mark?: string; endMark?: string };

/** Between two marks the fixes come every `everyS` seconds and the error is `noiseScale` times larger. */
export interface Canopy {
	fromMark: string;
	toMark: string;
	everyS: number;
	noiseScale: number;
}

export interface RunPlan {
	seed: number;
	steps: Step[];
	canopy?: Canopy[];
}

export interface SimulatedRun {
	/** Fixes as stored: 1e-6 degree integers and whole seconds after the first fix. */
	fixes: { latE6: number; lngE6: number; t: number }[];
	/** The noiseless position at each fix, for measuring the error. */
	truth: LatLng[];
	/** Seconds after the first fix at which each named instant happened. */
	marks: Record<string, number>;
}

interface Leg {
	t0: number;
	t1: number;
	path: LatLng[];
	cum: number[];
	speed: number;
}

export function simulate(plan: RunPlan): SimulatedRun {
	const legs: Leg[] = [];
	const marks: Record<string, number> = {};
	let t = 0;
	let here: LatLng | null = null;
	for (const s of plan.steps) {
		if (s.mark !== undefined) marks[s.mark] = t;
		if (s.kind === 'move') {
			const cum = [0];
			for (let i = 1; i < s.path.length; i++) cum.push(cum[i - 1] + hopM(s.path[i - 1], s.path[i]));
			const dur = cum[cum.length - 1] / s.speedMps;
			legs.push({ t0: t, t1: t + dur, path: s.path, cum, speed: s.speedMps });
			t += dur;
			here = s.path[s.path.length - 1];
		} else {
			if (here === null) throw new Error('a hold needs a place: start with a move');
			legs.push({ t0: t, t1: t + s.seconds, path: [here], cum: [0], speed: 0 });
			t += s.seconds;
		}
		if (s.endMark !== undefined) marks[s.endMark] = t;
	}
	const total = t;
	const windows = (plan.canopy ?? []).map((c) => {
		const from = marks[c.fromMark];
		const to = marks[c.toMark];
		if (from === undefined || to === undefined) throw new Error(`canopy marks ${c.fromMark}..${c.toMark} not in the plan`);
		return { from, to, everyS: c.everyS, noiseScale: c.noiseScale };
	});

	const rnd = mulberry32(plan.seed);
	const a = Math.exp(-1 / NOISE_TAU_S);
	const drive = NOISE_SIGMA_M * Math.sqrt(1 - a * a);
	let ex = NOISE_SIGMA_M * gaussian(rnd);
	let ey = NOISE_SIGMA_M * gaussian(rnd);

	const fixes: SimulatedRun['fixes'] = [];
	const truth: LatLng[] = [];
	let leg = 0;
	for (let s = 0; s <= Math.floor(total); s++) {
		if (s > 0) {
			ex = a * ex + drive * gaussian(rnd);
			ey = a * ey + drive * gaussian(rnd);
		}
		const wx = NOISE_WHITE_M * gaussian(rnd);
		const wy = NOISE_WHITE_M * gaussian(rnd);
		const w = windows.find((c) => s >= c.from && s <= c.to);
		if (w && Math.floor(s - w.from) % w.everyS !== 0) continue;
		while (leg < legs.length - 1 && legs[leg].t1 < s) leg++;
		const L = legs[leg];
		const p = positionOn(L, s);
		const scale = w ? w.noiseScale : 1;
		const noisy = offset(offset(p, 90, (ex + wx) * scale), 0, (ey + wy) * scale);
		fixes.push({ latE6: Math.round(noisy.lat * 1e6), lngE6: Math.round(noisy.lng * 1e6), t: s });
		truth.push(p);
	}
	return { fixes, truth, marks };
}

function positionOn(L: Leg, s: number): LatLng {
	if (L.speed === 0 || L.path.length === 1) return L.path[L.path.length - 1];
	const d = Math.min(Math.max(s - L.t0, 0) * L.speed, L.cum[L.cum.length - 1]);
	let i = 1;
	while (i < L.cum.length - 1 && L.cum[i] < d) i++;
	const span = L.cum[i] - L.cum[i - 1];
	const f = span > 0 ? (d - L.cum[i - 1]) / span : 0;
	const p = L.path[i - 1];
	const q = L.path[i];
	return { lat: p.lat + f * (q.lat - p.lat), lng: p.lng + f * (q.lng - p.lng) };
}

export function toTrack(fixes: SimulatedRun['fixes'], baseMs: number): TrackPoint[] {
	return fixes.map((f) => ({ lat: f.latE6 / 1e6, lng: f.lngE6 / 1e6, ts: new Date(baseMs + f.t * 1000).toISOString() }));
}

// ─────────────────────────── a day at the park ───────────────────────────

export const paceMps = (secondsPerKm: number) => 1000 / secondsPerKm;
const WALK_MPS = 1.35;

/** A minute in the lot waiting for a fix, then the walk to 20 m behind the start, jogged on to the line. */
function arrive(c: ParkCourse, speedMps: number, startMark = 'start'): Step[] {
	const sb = c.gates.start.bearingDeg;
	const behind = offset(c.line[0], sb, -20);
	const lot = offset(behind, sb + 180 + 35, 130);
	return [
		{ kind: 'move', path: [lot, lot], speedMps: WALK_MPS, mark: 'lot' },
		{ kind: 'hold', seconds: 60 },
		{ kind: 'move', path: [lot, behind], speedMps: WALK_MPS },
		{ kind: 'move', path: [behind, c.line[0]], speedMps, endMark: startMark },
	];
}

/** On past the finish line for 40 m easing off, then the walk back off the trail and a stop. */
function leave(from: LatLng, bearingDeg: number, speedMps: number): Step[] {
	const past = offset(from, bearingDeg, 40);
	const off = offset(past, bearingDeg + 60, 80);
	return [
		{ kind: 'move', path: [from, past], speedMps: speedMps * 0.7 },
		{ kind: 'move', path: [past, off], speedMps: WALK_MPS },
		{ kind: 'hold', seconds: 15, endMark: 'stopped' },
	];
}

function wholeCourse(c: ParkCourse, speedMps: number): Step[] {
	return [
		...arrive(c, speedMps),
		{ kind: 'move', path: c.line, speedMps, endMark: 'finish' },
		...leave(c.line[c.line.length - 1], c.gates.end.bearingDeg, speedMps),
	];
}

/** Out along the lead-in, `laps` laps of the loop, and back: a race course run for the wrong number of laps. */
function lapsPath(c: ParkCourse, laps: number): LatLng[] {
	const lap = (c.lineM - 2 * c.leadM) / c.laps;
	const parts = slice(c.line, 0, c.leadM + lap);
	for (let i = 1; i < laps; i++) parts.push(...slice(c.line, c.leadM, c.leadM + lap).slice(1));
	parts.push(...slice(c.line, c.lineM - c.leadM, c.lineM).slice(1));
	return parts;
}

export type Want =
	/** The run earns an effort timed between two marks of the plan. */
	| { effort: true; from: string; to: string }
	| { effort: false };

export interface CaseDef {
	/** A short stable handle, used by park_course_boards_test.sql. */
	key: string;
	name: string;
	course: string;
	why: string;
	plan: RunPlan;
	want: Want;
}

export function caseDefs(courses: readonly ParkCourse[]): CaseDef[] {
	const by = (slug: string) => {
		const c = courses.find((x) => x.slug === slug);
		if (!c) throw new Error(`course ${slug} is not in the manifest`);
		return c;
	};
	const beaver = by('beaver-lake-trail');
	const five = by('swift-creek-5k');
	const defs: CaseDef[] = [];
	const clean = (slug: string, secondsPerKm: number, seed: number) => {
		const c = by(slug);
		defs.push({
			key: `${short(slug)}_clean`,
			name: `${slug}: a clean run`,
			course: slug,
			why: `lot, start, the whole course at ${fmtPace(secondsPerKm)}/km, cool-down`,
			plan: { seed, steps: wholeCourse(c, paceMps(secondsPerKm)) },
			want: { effort: true, from: 'start', to: 'finish' },
		});
	};
	clean('beaver-lake-trail', 360, 101);
	clean('swift-creek-5k', 330, 102);
	clean('swift-creek-10k', 330, 103);
	clean('swift-creek-half', 345, 104);
	clean('swift-creek-marathon', 315, 105);
	clean('swift-creek-50k', 360, 106);

	// Beaver Lake: a stop at the bridge, and the woods past checkpoint 2 thin
	// the fixes to one every 8 s with the error 1.6 times larger.
	{
		const v = paceMps(360);
		const L = beaver.lineM;
		defs.push({
			key: 'beaver_canopy',
			name: 'beaver-lake-trail: a stop and a stretch of sparse fixes under the trees',
			course: beaver.slug,
			why: 'a 45 s stop at 2600 m with the recorder running, fixes every 8 s from 1500 m to 2100 m (checkpoint 2 is at 1797 m)',
			plan: {
				seed: 111,
				steps: [
					...arrive(beaver, v),
					{ kind: 'move', path: slice(beaver.line, 0, 1500), speedMps: v },
					{ kind: 'move', path: slice(beaver.line, 1500, 2100), speedMps: v, mark: 'canopy_in', endMark: 'canopy_out' },
					{ kind: 'move', path: slice(beaver.line, 2100, 2600), speedMps: v },
					{ kind: 'hold', seconds: 45 },
					{ kind: 'move', path: slice(beaver.line, 2600, L), speedMps: v, endMark: 'finish' },
					...leave(beaver.line[beaver.line.length - 1], beaver.gates.end.bearingDeg, v),
				],
				canopy: [{ fromMark: 'canopy_in', toMark: 'canopy_out', everyS: 8, noiseScale: 1.6 }],
			},
			want: { effort: true, from: 'start', to: 'finish' },
		});
		defs.push({
			key: 'beaver_shortcut',
			name: 'beaver-lake-trail: a shortcut across the loop that skips checkpoint 2',
			course: beaver.slug,
			why: 'the loop to 1245 m, straight across the neck of the spur checkpoint 2 sits on (125 m from it at the closest) to 1945 m, the rest of the loop: 407 m short, inside the 25 % length guard, so only the checkpoint refuses it',
			plan: {
				seed: 112,
				steps: [
					...arrive(beaver, v),
					{ kind: 'move', path: slice(beaver.line, 0, 1245), speedMps: v },
					{ kind: 'move', path: [slice(beaver.line, 1245, 1246)[0], slice(beaver.line, 1945, 1946)[0]], speedMps: v },
					{ kind: 'move', path: slice(beaver.line, 1945, L), speedMps: v, endMark: 'finish' },
					...leave(beaver.line[beaver.line.length - 1], beaver.gates.end.bearingDeg, v),
				],
			},
			want: { effort: false },
		});
		const reversed = [...beaver.line].reverse();
		const eb = beaver.gates.end.bearingDeg;
		const behind = offset(reversed[0], eb + 180, -20);
		const lot = offset(behind, eb + 35, 130);
		defs.push({
			key: 'beaver_wrong_way',
			name: 'beaver-lake-trail: the loop the wrong way round',
			course: beaver.slug,
			why: 'the whole loop counterclockwise from the same trailhead',
			plan: {
				seed: 113,
				steps: [
					{ kind: 'move', path: [lot, lot], speedMps: WALK_MPS, mark: 'lot' },
					{ kind: 'hold', seconds: 60 },
					{ kind: 'move', path: [lot, behind, reversed[0]], speedMps: WALK_MPS },
					{ kind: 'move', path: reversed, speedMps: v },
					...leave(reversed[reversed.length - 1], beaver.gates.start.bearingDeg + 180, v),
				],
			},
			want: { effort: false },
		});
		const short = slice(beaver.line, 0, L - 150);
		defs.push({
			key: 'beaver_short',
			name: 'beaver-lake-trail: stopping 150 m short of the finish',
			course: beaver.slug,
			why: 'every checkpoint passed, then the run ends 150 m before the line',
			plan: {
				seed: 114,
				steps: [
					...arrive(beaver, v),
					{ kind: 'move', path: short, speedMps: v },
					{ kind: 'hold', seconds: 30, endMark: 'stopped' },
				],
			},
			want: { effort: false },
		});
		const along = beaver.gates.start.bearingDeg + 90;
		const shifted = beaver.line.map((p) => offset(p, along, 60));
		defs.push({
			key: 'beaver_nearby',
			name: 'beaver-lake-trail: a run that only passes nearby',
			course: beaver.slug,
			why: 'the loop\'s own shape, 60 m along the start line from it: never crosses a line inside its 15 m reach',
			plan: {
				seed: 115,
				steps: [
					{ kind: 'move', path: [offset(shifted[0], along, 100), offset(shifted[0], along, 100)], speedMps: WALK_MPS, mark: 'lot' },
					{ kind: 'hold', seconds: 60 },
					{ kind: 'move', path: [offset(shifted[0], along, 100), shifted[0]], speedMps: WALK_MPS },
					{ kind: 'move', path: shifted, speedMps: v },
					{ kind: 'hold', seconds: 15, endMark: 'stopped' },
				],
			},
			want: { effort: false },
		});
		// Three laps back to back, the second fastest. On a loop whose start and
		// end lines sit on one point, the crossing that closes a lap never opens
		// the next, so laps 1 and 3 are passes and lap 2 is not (decisions
		// § 2402, m6). The fastest of 1 and 3 is the time.
		defs.push({
			key: 'beaver_three_laps',
			name: 'beaver-lake-trail: three laps back to back, the middle one fastest',
			course: beaver.slug,
			why: 'laps at 6:00, 4:30 and 5:30/km with no stop between: the lap that closes a pass never opens the next',
			plan: {
				seed: 116,
				steps: [
					...arrive(beaver, paceMps(360), 'lap1_start'),
					{ kind: 'move', path: beaver.line, speedMps: paceMps(360), endMark: 'lap1_end' },
					{ kind: 'move', path: beaver.line.slice(1), speedMps: paceMps(270), endMark: 'lap2_end' },
					{ kind: 'move', path: beaver.line.slice(1), speedMps: paceMps(330), endMark: 'lap3_end' },
					...leave(beaver.line[beaver.line.length - 1], beaver.gates.end.bearingDeg, paceMps(330)),
				],
			},
			want: { effort: true, from: 'lap2_end', to: 'lap3_end' },
		});
	}

	// Swift Creek 5K twice, walking back through the finish between them. The
	// two passes are separate crossings of the line, so both count and the
	// fastest is the time, whichever came first.
	for (const [slow, fast, seed, label] of [
		[390, 300, 121, 'slow then fast'],
		[300, 390, 122, 'fast then slow'],
	] as const) {
		const first = paceMps(slow);
		const second = paceMps(fast);
		const finish = five.line[five.line.length - 1];
		const turn = offset(finish, five.gates.end.bearingDeg, 25);
		defs.push({
			key: slow > fast ? '5k_two_passes_slow_fast' : '5k_two_passes_fast_slow',
			name: `swift-creek-5k: two passes in one run, ${label}`,
			course: five.slug,
			why: `a pass at ${fmtPace(slow)}/km, a minute's rest 25 m past the finish, then a pass at ${fmtPace(fast)}/km`,
			plan: {
				seed,
				steps: [
					...arrive(five, first, 'pass1_start'),
					{ kind: 'move', path: five.line, speedMps: first, endMark: 'pass1_end' },
					{ kind: 'move', path: [finish, turn], speedMps: first * 0.7 },
					{ kind: 'hold', seconds: 60 },
					{ kind: 'move', path: [turn, five.line[0]], speedMps: second, endMark: 'pass2_start' },
					{ kind: 'move', path: five.line, speedMps: second, endMark: 'pass2_end' },
					...leave(finish, five.gates.end.bearingDeg, second),
				],
			},
			want:
				slow > fast
					? { effort: true, from: 'pass2_start', to: 'pass2_end' }
					: { effort: true, from: 'pass1_start', to: 'pass1_end' },
		});
	}

	for (const [slug, secondsPerKm, seed] of [
		['swift-creek-10k', 330, 131],
		['swift-creek-marathon', 315, 132],
		['swift-creek-50k', 360, 133],
	] as const) {
		const c = by(slug);
		const v = paceMps(secondsPerKm);
		defs.push({
			key: `${short(slug)}_one_lap`,
			name: `${slug}: one lap of the two`,
			course: slug,
			why: 'out along the lead-in, one lap, back over the finish line: under the 25 % length guard',
			plan: {
				seed,
				steps: [
					...arrive(c, v),
					{ kind: 'move', path: lapsPath(c, 1), speedMps: v },
					...leave(c.line[c.line.length - 1], c.gates.end.bearingDeg, v),
				],
			},
			want: { effort: false },
		});
	}
	return defs;
}

/** `swift-creek-half` → `half`, `beaver-lake-trail` → `beaver`. */
function short(slug: string): string {
	return slug === 'beaver-lake-trail' ? 'beaver' : slug.replace('swift-creek-', '');
}

function fmtPace(s: number): string {
	return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

// ─────────────────────────── the fixture ───────────────────────────

export interface FixtureEffort {
	time_seconds: number;
	started_offset_ms: number;
	matched_by: string;
}

export interface FixtureCase {
	key: string;
	name: string;
	course: string;
	why: string;
	/** What the run should earn on its own course: the true elapsed time between the plan's marks, or nothing. */
	want: { effort: true; truth_s: number; tolerance_s: number } | { effort: false };
	/** What the matcher gave this run on every course of the park (only courses it timed). */
	matched: Record<string, FixtureEffort>;
	extent: { min_lat: number; min_lng: number; max_lat: number; max_lng: number };
	/** First fix [lat, lng] in 1e-6 degrees, then [dlat, dlng] per fix; 1 s apart unless `gaps` names [index, seconds]. */
	track: { first: [number, number]; d: number[]; gaps: [number, number][] };
}

export interface FixtureCourse {
	slug: string;
	geojson: string;
	distance_m: number;
	checkpoints: LatLng[];
	start_gate: { lat: number; lng: number; bearing_deg: number; half_width_m: number; source: string };
	end_gate: { lat: number; lng: number; bearing_deg: number; half_width_m: number; source: string };
}

export interface CourseRunFixture {
	_doc: string;
	base_time: string;
	courses: FixtureCourse[];
	cases: FixtureCase[];
}

export function encodeTrack(fixes: SimulatedRun['fixes']): FixtureCase['track'] {
	const d: number[] = [];
	const gaps: [number, number][] = [];
	for (let i = 1; i < fixes.length; i++) {
		d.push(fixes[i].latE6 - fixes[i - 1].latE6, fixes[i].lngE6 - fixes[i - 1].lngE6);
		const dt = fixes[i].t - fixes[i - 1].t;
		if (dt !== 1) gaps.push([i, dt]);
	}
	return { first: [fixes[0].latE6, fixes[0].lngE6], d, gaps };
}

export function decodeTrack(track: FixtureCase['track'], baseMs: number): TrackPoint[] {
	const gaps = new Map(track.gaps);
	let lat = track.first[0];
	let lng = track.first[1];
	let t = 0;
	const out: TrackPoint[] = [{ lat: lat / 1e6, lng: lng / 1e6, ts: new Date(baseMs).toISOString() }];
	for (let i = 1; i <= track.d.length / 2; i++) {
		lat += track.d[2 * i - 2];
		lng += track.d[2 * i - 1];
		t += gaps.get(i) ?? 1;
		out.push({ lat: lat / 1e6, lng: lng / 1e6, ts: new Date(baseMs + t * 1000).toISOString() });
	}
	return out;
}

function effortOf(e: GlobalSegmentEffortResult, baseMs: number): FixtureEffort {
	return {
		time_seconds: e.time_seconds,
		started_offset_ms: Date.parse(e.started_at) - baseMs,
		matched_by: e.matched_by,
	};
}

function gateJson(g: Gate, source: string) {
	return { lat: g.lat, lng: g.lng, bearing_deg: g.bearingDeg, half_width_m: g.halfWidthM, source };
}

export function buildCourseRunFixture(read: RepoReader): CourseRunFixture {
	const courses = loadCourses(read);
	const baseMs = Date.parse(BASE_TIME);
	const cases: FixtureCase[] = caseDefs(courses).map((def) => {
		const run = simulate(def.plan);
		const encoded = encodeTrack(run.fixes);
		const track = decodeTrack(encoded, baseMs);
		const results = computeGlobalSegmentEfforts(track, courses.map((c) => c.geometry));
		const matched: Record<string, FixtureEffort> = {};
		results.forEach((r, i) => {
			if (r) matched[courses[i].slug] = effortOf(r, baseMs);
		});
		let want: FixtureCase['want'] = { effort: false };
		const w = def.want;
		if (w.effort) {
			const from = run.marks[w.from];
			const to = run.marks[w.to];
			const speed = def.plan.steps.find((s) => s.kind === 'move' && s.endMark === w.to);
			const v = speed && speed.kind === 'move' ? speed.speedMps : paceMps(360);
			want = { effort: true, truth_s: round3(to - from), tolerance_s: round3((2 * LINE_ERROR_M) / v) };
		}
		let minLat = Infinity;
		let minLng = Infinity;
		let maxLat = -Infinity;
		let maxLng = -Infinity;
		for (const p of track) {
			minLat = Math.min(minLat, p.lat);
			maxLat = Math.max(maxLat, p.lat);
			minLng = Math.min(minLng, p.lng);
			maxLng = Math.max(maxLng, p.lng);
		}
		return {
			key: def.key,
			name: def.name,
			course: def.course,
			why: def.why,
			want,
			matched,
			extent: { min_lat: minLat, min_lng: minLng, max_lat: maxLat, max_lng: maxLng },
			track: encoded,
		};
	});
	return {
		_doc:
			'Synthetic runs over the six Pocahontas park courses (issue #1342 step 5c), generated by apps/web/src/lib/parks/course_run_fixture.ts through scripts/gen_park_course_runs.mjs; do not edit by hand. Read by apps/web/src/lib/parks/park_course_runs.test.ts, apps/mobile_android/test/park_course_runs_test.dart and supabase/functions/segment-match/park_course_runs.test.ts; park_course_boards_test.sql carries the matched efforts. Each course line is the committed GeoJSON named; the lines are what the database derives (or the curated line). `matched` is the matcher\'s result on every course, `want` what the case is for: an effort within tolerance_s of truth_s on its own course, or none.',
		base_time: BASE_TIME,
		courses: courses.map((c) => ({
			slug: c.slug,
			geojson: c.geojson,
			distance_m: c.distanceM,
			checkpoints: c.checkpoints,
			start_gate: gateJson(c.gates.start, c.gateSources.start),
			end_gate: gateJson(c.gates.end, c.gateSources.end),
		})),
		cases,
	};
}

const round3 = (x: number) => Math.round(x * 1000) / 1000;

/** The fixture as committed: objects one key a line, arrays of numbers on one line. */
export function formatFixture(value: unknown, indent = ''): string {
	const inner = `${indent}\t`;
	if (Array.isArray(value)) {
		if (value.every((v) => v === null || typeof v !== 'object' || Array.isArray(v))) {
			return `[${value.map((v) => JSON.stringify(v)).join(",")}]`;
		}
		return `[\n${value.map((v) => inner + formatFixture(v, inner)).join(',\n')}\n${indent}]`;
	}
	if (value !== null && typeof value === 'object') {
		const entries = Object.entries(value as Record<string, unknown>);
		if (entries.length === 0) return '{}';
		return `{\n${entries.map(([k, v]) => `${inner}${JSON.stringify(k)}: ${formatFixture(v, inner)}`).join(',\n')}\n${indent}}`;
	}
	return JSON.stringify(value);
}
