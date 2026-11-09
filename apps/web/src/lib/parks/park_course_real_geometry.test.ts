// The park-course matcher on the real Pocahontas course lines (#1342): a run
// that follows a course is timed once, and a partial or foreign lap is not.
//
// The lines are derived here as the `global_segments_set_gates` trigger
// derives them (migration 20271122002402 over 20271116002390's
// `private.course_end_bearing`). No TS port of that derivation exists, so
// `derivedGates` replicates it: the start line on the first point facing the
// point 25 m along, the end line on the last point facing from the point 25 m
// before, none when under 10 m of line survives, half-width 15 m.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { TrackPoint } from '../types';
import {
	GATE_EARTH_RADIUS_M,
	GATE_HALF_WIDTH_SEGMENT_M,
	crossingsOf,
	type Gate,
	type GateFix,
} from '../geo/gate_crossing';
import { computeGlobalSegmentEfforts, type GlobalSegmentGeometry } from '../segments/segments';

const PARK = resolve(
	dirname(fileURLToPath(import.meta.url)),
	'../../../../../scripts/parks/catalogue/us-va/pocahontas',
);

interface LatLng {
	lat: number;
	lng: number;
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
}

const manifest = JSON.parse(readFileSync(resolve(PARK, 'manifest.json'), 'utf8')) as {
	courses: ManifestCourse[];
	race_courses: ManifestCourse[];
};
const COURSES: ManifestCourse[] = [...manifest.courses, ...manifest.race_courses];

function courseLine(c: ManifestCourse): LatLng[] {
	const gj = JSON.parse(readFileSync(resolve(PARK, c.geojson), 'utf8'));
	const line = gj.features.find((f: { geometry?: { type?: string } }) => f.geometry?.type === 'LineString');
	return line.geometry.coordinates.map((p: number[]) => ({ lat: p[1], lng: p[0] }));
}

const rad = (d: number) => (d * Math.PI) / 180;

function planeXY(lat0: number, lng0: number, lat: number, lng: number): { x: number; y: number } {
	let dl = lng - lng0;
	if (dl >= 180) dl -= 360;
	else if (dl < -180) dl += 360;
	return {
		x: rad(dl) * GATE_EARTH_RADIUS_M * Math.cos(rad(lat0)),
		y: rad(lat - lat0) * GATE_EARTH_RADIUS_M,
	};
}

function bearingOf(x: number, y: number): number {
	const b = (((Math.atan2(x, y) * 180) / Math.PI + 360) % 360 + 360) % 360;
	return b >= 360 ? b - 360 : b;
}

function courseEndBearing(geom: LatLng[], finish: boolean): number | null {
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

function derivedGates(line: LatLng[]): { start: Gate; end: Gate } {
	const sb = courseEndBearing(line, false);
	const eb = courseEndBearing(line, true);
	assert.ok(sb !== null && eb !== null, 'both ends derive a line');
	const first = line[0];
	const last = line[line.length - 1];
	return {
		start: { lat: first.lat, lng: first.lng, bearingDeg: sb, halfWidthM: GATE_HALF_WIDTH_SEGMENT_M },
		end: { lat: last.lat, lng: last.lng, bearingDeg: eb, halfWidthM: GATE_HALF_WIDTH_SEGMENT_M },
	};
}

function hopM(a: LatLng, b: LatLng): number {
	const dLat = rad(b.lat - a.lat);
	const dLng = rad(b.lng - a.lng);
	const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
	return 2 * GATE_EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

function lengthM(pts: LatLng[]): number {
	let t = 0;
	for (let i = 1; i < pts.length; i++) t += hopM(pts[i - 1], pts[i]);
	return t;
}

/** The polyline between fromM and toM metres along it, cut ends interpolated. */
function slice(pts: LatLng[], fromM: number, toM: number): LatLng[] {
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

function offset(p: LatLng, bearingDeg: number, distM: number): LatLng {
	const x = distM * Math.sin(rad(bearingDeg));
	const y = distM * Math.cos(rad(bearingDeg));
	return {
		lat: p.lat + (y / GATE_EARTH_RADIUS_M) * (180 / Math.PI),
		lng: p.lng + (x / (GATE_EARTH_RADIUS_M * Math.cos(rad(p.lat)))) * (180 / Math.PI),
	};
}

const SPEED_MPS = 1000 / 300;
const APPROACH_M = 50;
const T0 = Date.parse('2026-11-14T13:00:00Z');

function mulberry32(seed: number): () => number {
	let a = seed >>> 0;
	return () => {
		a = (a + 0x6d2b79f5) >>> 0;
		let t = a;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

/**
 * A run along `path` at 5:00/km with a fix each second, a straight approach
 * and run-out of 50 m along the course's own start and end bearings, and up to
 * about 3 m of deterministic jitter (two slow sinusoids plus a little noise).
 */
function syntheticRun(path: LatLng[], gates: { start: Gate; end: Gate }, seed: number): TrackPoint[] {
	const route = [
		offset(path[0], gates.start.bearingDeg, -APPROACH_M),
		...path,
		offset(path[path.length - 1], gates.end.bearingDeg, APPROACH_M),
	];
	const cum = [0];
	for (let i = 1; i < route.length; i++) cum.push(cum[i - 1] + hopM(route[i - 1], route[i]));
	const total = cum[cum.length - 1];
	const rnd = mulberry32(seed);
	const ph = [rnd(), rnd(), rnd(), rnd()].map((v) => v * 2 * Math.PI);
	const out: TrackPoint[] = [];
	let seg = 1;
	for (let t = 0; t * SPEED_MPS <= total; t++) {
		const d = t * SPEED_MPS;
		while (seg < route.length - 1 && cum[seg] < d) seg++;
		const a = route[seg - 1];
		const b = route[seg];
		const span = cum[seg] - cum[seg - 1];
		const f = span > 0 ? (d - cum[seg - 1]) / span : 0;
		const base = { lat: a.lat + f * (b.lat - a.lat), lng: a.lng + f * (b.lng - a.lng) };
		const east = 2 * Math.sin((2 * Math.PI * t) / 37 + ph[0]) + 0.8 * Math.sin((2 * Math.PI * t) / 11 + ph[1]) + (rnd() - 0.5) * 0.8;
		const north = 2 * Math.sin((2 * Math.PI * t) / 41 + ph[2]) + 0.8 * Math.sin((2 * Math.PI * t) / 13 + ph[3]) + (rnd() - 0.5) * 0.8;
		const p = offset(offset(base, 90, east), 0, north);
		out.push({ lat: p.lat, lng: p.lng, ts: new Date(T0 + t * 1000).toISOString() });
	}
	return out;
}

interface Built {
	course: ManifestCourse;
	line: LatLng[];
	lineM: number;
	gates: { start: Gate; end: Gate };
	geometry: GlobalSegmentGeometry;
}

const BUILT: Built[] = COURSES.map((course) => {
	const line = courseLine(course);
	const gates = derivedGates(line);
	return {
		course,
		line,
		lineM: lengthM(line),
		gates,
		geometry: {
			points: line,
			distance_m: course.distance_m,
			checkpoints: course.checkpoints,
			startGate: gates.start,
			endGate: gates.end,
		},
	};
});

const bySlug = (slug: string): Built => {
	const b = BUILT.find((x) => x.course.slug === slug);
	assert.ok(b, `course ${slug} is in the manifest`);
	return b;
};

/** Metres from the start line to the junction where the lead-in meets the loop. */
function lineToJunctionM(b: Built): number {
	return (b.course.lead_in_m as number) - (b.course.start_line_from_lead_in_start_m as number);
}

/** The course run for `laps` laps of its loop: out along the lead-in, round, and back. */
function lapsPath(b: Built, laps: number): LatLng[] {
	const lead = lineToJunctionM(b);
	const lap = (b.lineM - 2 * lead) / (b.course.laps as number);
	const parts: LatLng[] = slice(b.line, 0, lead + lap);
	for (let i = 1; i < laps; i++) parts.push(...slice(b.line, lead, lead + lap).slice(1));
	parts.push(...slice(b.line, b.lineM - lead, b.lineM).slice(1));
	return parts;
}

function fixesOf(track: TrackPoint[]): GateFix[] {
	const out: GateFix[] = [];
	let covered = 0;
	for (let i = 0; i < track.length; i++) {
		if (i > 0) covered += hopM(track[i - 1], track[i]);
		out.push({ lat: track[i].lat, lng: track[i].lng, tMs: Date.parse(track[i].ts as string), coveredM: covered });
	}
	return out;
}

/** Every crossing of the course's lines by `track`, for a failure message. */
function diagnose(b: Built, track: TrackPoint[]): string {
	const fixes = fixesOf(track);
	const fmt = (name: string, g: Gate) =>
		`${name} line ${g.lat.toFixed(6)},${g.lng.toFixed(6)} bearing ${g.bearingDeg.toFixed(1)}: ` +
		crossingsOf(fixes, g)
			.map((c) => `${c.direction} at t=${((c.tMs - T0) / 1000).toFixed(1)}s covered=${c.coveredM.toFixed(0)}m offset=${c.offsetM.toFixed(1)}m`)
			.join('; ');
	return `${b.course.slug} (line ${b.lineM.toFixed(0)} m, ${track.length} fixes)\n  ${fmt('start', b.gates.start)}\n  ${fmt('end', b.gates.end)}`;
}

function score(b: Built, track: TrackPoint[]) {
	return computeGlobalSegmentEfforts(track, [b.geometry])[0];
}

test('the derived start and end lines sit on one point, as the manifest places them', () => {
	for (const b of BUILT) {
		const apart = hopM(b.gates.start, b.gates.end);
		assert.ok(apart <= 25, `${b.course.slug}: start and end lines ${apart.toFixed(1)} m apart`);
	}
});

for (const [i, b] of BUILT.entries()) {
	test(`${b.course.slug}: a run of the whole course at 5:00/km is timed once, at distance over speed`, () => {
		const track = syntheticRun(b.line, b.gates, 1000 + i);
		const effort = score(b, track);
		assert.ok(effort, `no effort\n${diagnose(b, track)}`);
		assert.equal(effort.matched_by, 'gate');
		const expected = b.lineM / SPEED_MPS;
		assert.ok(
			Math.abs(effort.time_seconds - expected) <= 3,
			`timed ${effort.time_seconds.toFixed(1)} s, expected ${expected.toFixed(1)} s\n${diagnose(b, track)}`,
		);
		assert.ok(Math.abs(b.lineM / b.course.distance_m - 1) < 0.001, `${b.course.slug}: the line measures its distance`);
	});
}

for (const slug of ['swift-creek-10k', 'swift-creek-marathon', 'swift-creek-50k']) {
	test(`${slug}: one lap of the two, with both lead-ins, gets no effort`, () => {
		const b = bySlug(slug);
		const track = syntheticRun(lapsPath(b, 1), b.gates, 2000);
		const effort = score(b, track);
		assert.equal(effort, null, `timed ${effort?.time_seconds} s on one lap\n${diagnose(b, track)}`);
	});

	test(`${slug}: three laps of the two are not timed, because the one pass is over the length guard`, () => {
		const b = bySlug(slug);
		const track = syntheticRun(lapsPath(b, 3), b.gates, 3000);
		const effort = score(b, track);
		assert.equal(effort, null, `timed ${effort?.time_seconds} s on three laps\n${diagnose(b, track)}`);
	});
}

test('swift-creek-5k and swift-creek-10k: a run of one is not timed on the other', () => {
	const five = bySlug('swift-creek-5k');
	const ten = bySlug('swift-creek-10k');
	const fiveRun = syntheticRun(five.line, five.gates, 4000);
	const tenRun = syntheticRun(ten.line, ten.gates, 4001);
	const tenOnFive = score(five, tenRun);
	const fiveOnTen = score(ten, fiveRun);
	assert.equal(tenOnFive, null, `a 10K run timed ${tenOnFive?.time_seconds} s on the 5K\n${diagnose(five, tenRun)}`);
	assert.equal(fiveOnTen, null, `a 5K run timed ${fiveOnTen?.time_seconds} s on the 10K\n${diagnose(ten, fiveRun)}`);
});

/** The course's own direction at a line: the bearing over its first (or last) few metres. */
function courseDirectionAt(b: Built, finish: boolean): number {
	const span = slice(b.line, finish ? b.lineM - 5 : 0, finish ? b.lineM : 5);
	const o = span[0];
	const { x, y } = planeXY(o.lat, o.lng, span[span.length - 1].lat, span[span.length - 1].lng);
	return bearingOf(x, y);
}

function angleApart(a: number, b: number): number {
	const d = Math.abs(a - b) % 360;
	return d > 180 ? 360 - d : d;
}

for (const b of BUILT) {
	test(`${b.course.slug}: each derived line faces the course's own direction at it, within 10 degrees`, () => {
		const start = angleApart(b.gates.start.bearingDeg, courseDirectionAt(b, false));
		const end = angleApart(b.gates.end.bearingDeg, courseDirectionAt(b, true));
		assert.ok(start <= 10, `${b.course.slug}: start line ${start.toFixed(1)} degrees off the course`);
		assert.ok(end <= 10, `${b.course.slug}: end line ${end.toFixed(1)} degrees off the course`);
	});
}

test('the half, marathon and 50K share a start area, and a run of one is not timed on another', () => {
	const slugs = ['swift-creek-half', 'swift-creek-marathon', 'swift-creek-50k'];
	for (const [i, run] of slugs.entries()) {
		const ran = bySlug(run);
		const track = syntheticRun(ran.line, ran.gates, 5000 + i);
		for (const other of slugs) {
			if (other === run) continue;
			const course = bySlug(other);
			const effort = score(course, track);
			assert.equal(effort, null, `a ${run} run timed ${effort?.time_seconds} s on the ${other}\n${diagnose(course, track)}`);
		}
	}
});
