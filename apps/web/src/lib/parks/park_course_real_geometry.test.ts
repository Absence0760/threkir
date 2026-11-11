// The park-course matcher on the real Pocahontas course lines (#1342): a run
// that follows a course is timed once, and a partial or foreign lap is not.
//
// The lines are derived as the `global_segments_set_gates` trigger derives
// them (migration 20271122002402 over 20271116002390's
// `private.course_end_bearing`), by `derivedGates` in course_run_fixture.ts:
// the start line on the first point facing the point 25 m along, the end line
// on the last point facing from the point 25 m before, none when under 10 m of
// line survives, half-width 15 m. Where the manifest carries a curated
// `start_gate` / `end_gate` for an end, the load writes it as a curator line,
// which the trigger never re-derives, so that end is timed by the curated
// line instead (decisions § 2424). park_course_boards_test.sql checks the
// database holds exactly these lines.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import type { TrackPoint } from '../types';
import { crossingsOf, type Gate, type GateFix } from '../geo/gate_crossing';
import { computeGlobalSegmentEfforts, type GlobalSegmentGeometry } from '../segments/segments';
import {
	bearingOf,
	derivedGates,
	hopM,
	loadCourses,
	mulberry32,
	offset,
	planeXY,
	slice,
	type LatLng,
	type ParkCourse,
} from './course_run_fixture';

const ROOT = resolve(import.meta.dirname, '../../../../..');

const SPEED_MPS = 1000 / 300;
const APPROACH_M = 50;
const T0 = Date.parse('2026-11-14T13:00:00Z');

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
	course: ParkCourse;
	line: LatLng[];
	lineM: number;
	gates: { start: Gate; end: Gate };
	geometry: GlobalSegmentGeometry;
}

const BUILT: Built[] = loadCourses((path) => readFileSync(resolve(ROOT, path), 'utf8')).map((course) => ({
	course,
	line: course.line,
	lineM: course.lineM,
	gates: course.gates,
	geometry: course.geometry,
}));

const bySlug = (slug: string): Built => {
	const b = BUILT.find((x) => x.course.slug === slug);
	assert.ok(b, `course ${slug} is in the manifest`);
	return b;
};

/** Metres from the start line to the junction where the lead-in meets the loop. */
function lineToJunctionM(b: Built): number {
	return b.course.leadM;
}

/** The course run for `laps` laps of its loop: out along the lead-in, round, and back. */
function lapsPath(b: Built, laps: number): LatLng[] {
	const lead = lineToJunctionM(b);
	const lap = (b.lineM - 2 * lead) / b.course.laps;
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

test('the start and end lines sit on one point, as the manifest places them', () => {
	for (const b of BUILT) {
		const apart = hopM(b.gates.start, b.gates.end);
		assert.ok(apart <= 25, `${b.course.slug}: start and end lines ${apart.toFixed(1)} m apart`);
	}
});

// A run of each whole course, and one lap of a two-lap course, are cases of
// fixtures/park_course_runs.json (park_course_runs.test.ts), with the GPS
// error a phone records.
test('each course line measures its manifest distance', () => {
	for (const b of BUILT) {
		assert.ok(Math.abs(b.lineM / b.course.distanceM - 1) < 0.001, `${b.course.slug}: ${b.lineM.toFixed(1)} m`);
	}
});

for (const slug of ['swift-creek-10k', 'swift-creek-marathon', 'swift-creek-50k']) {
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
	test(`${b.course.slug}: each line it is timed by faces the course's own direction at it, within 10 degrees`, () => {
		const start = angleApart(b.gates.start.bearingDeg, courseDirectionAt(b, false));
		const end = angleApart(b.gates.end.bearingDeg, courseDirectionAt(b, true));
		assert.ok(start <= 10, `${b.course.slug}: start line ${start.toFixed(1)} degrees off the course`);
		assert.ok(end <= 10, `${b.course.slug}: end line ${end.toFixed(1)} degrees off the course`);
	});
}

test('a curated line sits only where the derived one would face off the course', () => {
	for (const b of BUILT) {
		const derived = derivedGates(b.line);
		for (const [finish, curated, d] of [
			[false, b.course.gateSources.start === 'curator', derived.start],
			[true, b.course.gateSources.end === 'curator', derived.end],
		] as const) {
			const off = angleApart(d.bearingDeg, courseDirectionAt(b, finish));
			assert.equal(
				curated,
				off > 10,
				`${b.course.slug} ${finish ? 'end' : 'start'}: derived ${off.toFixed(1)} degrees off, curated ${curated}`,
			);
		}
	}
});

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
