import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
	COURSE_GATE_AGAINST_ROUTE_DEG,
	COURSE_GATE_DEFAULT_HALF_WIDTH_M,
	COURSE_GATE_HALF_WIDTH_MAX_M,
	COURSE_GATE_HALF_WIDTH_MIN_M,
	COURSE_GATE_ROUTE_WARN_M,
	COURSE_GATE_BOX_DEPTH_M,
	COURSE_GATE_SHARED_SPOT_DEG,
	COURSE_GATE_SHARED_SPOT_M,
	bearingTo,
	clampHalfWidth,
	courseGate,
	gateArrowTip,
	gateLineEnds,
	gateBox,
	gateBoxParts,
	gateTimingEdges,
	gatePointAlong,
	gatesShareSpot,
	type GateBoxSide,
	gateRouteRelation,
	gateWarnings,
	normalizeBearing,
	preflightBlocks,
	racePreflight,
	type CourseGate,
	type CourseGateColumns,
	type GateWhich,
	type GatePoint,
	type PreflightCourse,
	type SessionStartMode,
} from './course_gates';

// The TS reader of fixtures/course_gates_cases.json, the case table the
// course_gates pair shares with apps/mobile_android/test/course_gates_test.dart.
// The file's own `schema` block says what each section means.

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..', '..');
const fixture = JSON.parse(
	readFileSync(join(REPO, 'fixtures', 'course_gates_cases.json'), 'utf-8'),
) as Record<string, unknown>;

const SECTIONS = [
	'normalizeBearing',
	'clampHalfWidth',
	'courseGate',
	'bearingTo',
	'lineEnds',
	'arrowTip',
	'routeRelation',
	'warnings',
	'preflight',
	'pointAlong',
	'boxCorners',
	'sharedSpot',
	'boxParts',
	'timingEdges',
];
const META = new Set([
	'spec',
	'reference',
	'readers',
	'schema',
	'constants',
	'degreeTolerance',
	'bearingTolerance',
	'distanceToleranceM',
]);

type Obj = Record<string, unknown>;

function num(v: unknown): number {
	if (v === 'NaN') return NaN;
	return v as number;
}

const DEG = fixture.degreeTolerance as number;
const BEARING = fixture.bearingTolerance as number;
const DIST = fixture.distanceToleranceM as number;

function near(actual: number, expected: number, tol: number, what: string) {
	assert.ok(Math.abs(actual - expected) <= tol, `${what}: ${actual} vs ${expected}`);
}

function nearPoint(actual: GatePoint, expected: Obj, what: string) {
	near(actual.lat, expected.lat as number, DEG, `${what} lat`);
	near(actual.lng, expected.lng as number, DEG, `${what} lng`);
}

function nearBearing(actual: number, expected: number, what: string) {
	const d = Math.abs(actual - expected);
	assert.ok(Math.min(d, 360 - d) <= BEARING, `${what}: ${actual} vs ${expected}`);
}

function gate(o: Obj): CourseGate {
	return {
		lat: o.lat as number,
		lng: o.lng as number,
		bearingDeg: o.bearingDeg as number,
		halfWidthM: o.halfWidthM as number,
		source: (o.source as 'derived' | 'organiser' | undefined) ?? 'derived',
	};
}

function route(v: unknown): GatePoint[] | null {
	return v === null ? null : (v as Obj[]).map((p) => ({ lat: p.lat as number, lng: p.lng as number }));
}

function cases(section: string): Obj[] {
	return fixture[section] as Obj[];
}

test('the reader knows every section the file holds', () => {
	for (const key of Object.keys(fixture)) {
		assert.ok(META.has(key) || SECTIONS.includes(key), `unknown section ${key}`);
	}
	for (const s of SECTIONS) assert.ok(cases(s).length > 0, `section ${s} is empty`);
	assert.equal(fixture.spec, 'course_gates v1');
});

test('constants match the case table', () => {
	const c = fixture.constants as Obj;
	assert.equal(COURSE_GATE_HALF_WIDTH_MIN_M, c.halfWidthMinM);
	assert.equal(COURSE_GATE_HALF_WIDTH_MAX_M, c.halfWidthMaxM);
	assert.equal(COURSE_GATE_DEFAULT_HALF_WIDTH_M, c.defaultHalfWidthM);
	assert.equal(COURSE_GATE_ROUTE_WARN_M, c.routeWarnM);
	assert.equal(COURSE_GATE_AGAINST_ROUTE_DEG, c.againstRouteDeg);
	assert.equal(COURSE_GATE_BOX_DEPTH_M, c.boxDepthM);
	assert.equal(COURSE_GATE_SHARED_SPOT_M, c.sharedSpotM);
	assert.equal(COURSE_GATE_SHARED_SPOT_DEG, c.sharedSpotDeg);
});

test('normalizeBearing', () => {
	for (const c of cases('normalizeBearing')) {
		assert.equal(normalizeBearing(c.in as number), c.out, String(c.note));
	}
});

test('clampHalfWidth', () => {
	for (const c of cases('clampHalfWidth')) {
		assert.equal(clampHalfWidth(num(c.in)), c.out, String(c.note));
	}
});

test('courseGate', () => {
	for (const c of cases('courseGate')) {
		const got = courseGate(c.row as unknown as CourseGateColumns, c.which as GateWhich);
		assert.deepEqual(got, c.expected, String(c.note));
	}
});

test('bearingTo', () => {
	for (const c of cases('bearingTo')) {
		nearBearing(bearingTo(c.from as GatePoint, c.to as GatePoint), c.bearingDeg as number, String(c.note));
	}
});

test('gateLineEnds', () => {
	for (const c of cases('lineEnds')) {
		const [left, right] = gateLineEnds(gate(c.gate as Obj));
		nearPoint(left, c.left as Obj, `${c.note} left`);
		nearPoint(right, c.right as Obj, `${c.note} right`);
	}
});

test('gateArrowTip', () => {
	for (const c of cases('arrowTip')) {
		nearPoint(gateArrowTip(gate(c.gate as Obj)), c.tip as Obj, String(c.note));
	}
});

test('gateRouteRelation', () => {
	for (const c of cases('routeRelation')) {
		const got = gateRouteRelation(gate(c.gate as Obj), route(c.route)!);
		const want = c.expected as Obj | null;
		if (want === null) {
			assert.equal(got, null, String(c.note));
			continue;
		}
		assert.ok(got !== null, String(c.note));
		near(got.distanceM, want.distanceM as number, DIST, `${c.note} distance`);
		nearBearing(got.routeBearingDeg, want.routeBearingDeg as number, `${c.note} bearing`);
		assert.equal(got.against, want.against, `${c.note} against`);
	}
});

test('gateWarnings', () => {
	for (const c of cases('warnings')) {
		const got = gateWarnings({
			which: c.which as GateWhich,
			gate: c.gate === null ? null : gate(c.gate as Obj),
			route: route(c.route),
			selfCross: c.selfCross as boolean,
			mode: c.mode as SessionStartMode,
		});
		assert.deepEqual(got, c.expected, String(c.note));
	}
});

test('racePreflight and preflightBlocks', () => {
	for (const c of cases('preflight')) {
		const courses: PreflightCourse[] = (c.courses as Obj[]).map((o) => ({
			id: o.id as string,
			startGate: o.startGate === null ? null : gate(o.startGate as Obj),
			finishGate: o.finishGate === null ? null : gate(o.finishGate as Obj),
			hasFinishPoint: o.hasFinishPoint as boolean,
			selfCross: o.selfCross as boolean,
			route: route(o.route),
		}));
		const got = racePreflight(courses, c.mode as SessionStartMode).map((i) => ({
			courseId: i.courseId,
			code: i.code,
			severity: i.severity,
			which: i.which ?? null,
		}));
		assert.deepEqual(got, c.expected, String(c.note));
		assert.equal(preflightBlocks(racePreflight(courses, c.mode as SessionStartMode)), c.blocks, String(c.note));
	}
});

test('gatePointAlong', () => {
	for (const c of cases('pointAlong')) {
		nearPoint(gatePointAlong(gate(c.gate as Obj), c.f as number), c.point as Obj, String(c.note));
	}
});

function nearPoints(actual: GatePoint[], expected: Obj[], what: string) {
	assert.equal(actual.length, expected.length, `${what}: point count`);
	actual.forEach((p, i) => nearPoint(p, expected[i], `${what} [${i}]`));
}

test('gateBox', () => {
	for (const c of cases('boxCorners')) {
		const got = gateBox(
			gate(c.gate as Obj),
			c.depthM as number,
			c.side as GateBoxSide,
			c.from as number,
			c.to as number,
		);
		nearPoints(got, c.corners as Obj[], String(c.note));
	}
});

test('gatesShareSpot', () => {
	for (const c of cases('sharedSpot')) {
		assert.equal(gatesShareSpot(gate(c.start as Obj), gate(c.finish as Obj)), c.shared, String(c.note));
	}
});

test('gateBoxParts', () => {
	for (const c of cases('boxParts')) {
		const got = gateBoxParts(
			c.start === null ? null : gate(c.start as Obj),
			c.finish === null ? null : gate(c.finish as Obj),
			c.depthM as number,
		);
		const note = String(c.note);
		assert.equal(got.layout, c.layout, `${note} layout`);
		const want = c.parts as Obj[];
		assert.equal(got.parts.length, want.length, `${note} part count`);
		got.parts.forEach((p, i) => {
			const w = want[i];
			assert.equal(p.which, w.which, `${note} [${i}] which`);
			nearPoints(p.box, w.box as Obj[], `${note} [${i}] box`);
			nearPoints(p.line, w.line as Obj[], `${note} [${i}] line`);
		});
		const marks = c.markers as Obj[];
		assert.equal(got.markers.length, marks.length, `${note} marker count`);
		got.markers.forEach((mk, i) => {
			assert.equal(mk.which, marks[i].which, `${note} marker [${i}] which`);
			nearPoint(mk.at, marks[i].at as Obj, `${note} marker [${i}]`);
		});
	}
});

test('gateTimingEdges', () => {
	for (const c of cases('timingEdges')) {
		const got = gateTimingEdges(gate(c.start as Obj), gate(c.finish as Obj), c.depthM as number);
		const note = String(c.note);
		assert.equal(got.layout, c.layout, `${note} layout`);
		assert.equal(got.depthM, c.depthM, `${note} depth`);
		for (const key of ['startExit', 'finishEntry'] as const) {
			const want = c[key] as Obj;
			nearPoint(got[key], want, `${note} ${key}`);
			nearBearing(got[key].bearingDeg, want.bearingDeg as number, `${note} ${key} bearing`);
			assert.equal(got[key].halfWidthM, want.halfWidthM, `${note} ${key} half-width`);
		}
	}
});
