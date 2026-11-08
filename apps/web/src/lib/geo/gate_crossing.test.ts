import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
	GATE_EARTH_RADIUS_M,
	GATE_HALF_WIDTH_RACE_M,
	GATE_HALF_WIDTH_SEGMENT_M,
	GATE_MAX_GAP_S,
	GATE_MAX_HOP_M,
	GATE_REJECT_GAP_S,
	GateCrossingDetector,
	crossingsOf,
	gateProjection,
	type Gate,
	type GateCrossing,
	type GateCrossingOptions,
	type GateFix,
} from './gate_crossing';

// The TS reader of fixtures/gate_crossing_cases.json, the case table the
// gate_crossing pair shares with apps/mobile_android/test/gate_crossing_test.dart
// and Wear's GateCrossingTest.kt. The file's own `schema` block says what each
// section means.

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..', '..');
const fixture = JSON.parse(
	readFileSync(join(REPO, 'fixtures', 'gate_crossing_cases.json'), 'utf-8'),
) as Record<string, unknown>;

const SECTIONS = ['projection', 'crossings'];
const META = new Set([
	'spec',
	'reference',
	'readers',
	'schema',
	'constants',
	't0EpochMs',
	'distanceToleranceM',
	'timeToleranceS',
	'fractionTolerance',
]);

type Obj = Record<string, unknown>;

function num(v: unknown): number {
	if (v === 'NaN') return NaN;
	if (v === 'Infinity') return Infinity;
	if (v === '-Infinity') return -Infinity;
	if (typeof v === 'number') return v;
	throw new Error(`not a fixture number: ${String(v)}`);
}

function req(o: Obj, key: string): unknown {
	if (!(key in o)) throw new Error(`case ${String(o.name)} has no '${key}' (nullable fields are explicit)`);
	return o[key];
}

const constants = fixture.constants as Obj;
const t0 = num(fixture.t0EpochMs);
const distTol = num(fixture.distanceToleranceM);
const timeTol = num(fixture.timeToleranceS);
const fracTol = num(fixture.fractionTolerance);
const K = (num(constants.EARTH_RADIUS_M) * Math.PI) / 180;

function section(name: string): Obj[] {
	return fixture[name] as Obj[];
}

function gateOf(o: Obj): Gate {
	return {
		lat: num(o.lat),
		lng: num(o.lng),
		bearingDeg: num(o.bearingDeg),
		halfWidthM: num(o.halfWidthM),
	};
}

function position(gate: Gate, o: Obj): { lat: number; lng: number } {
	if ('lat' in o) return { lat: num(o.lat), lng: num(o.lng) };
	return {
		lat: gate.lat + num(o.northM) / K,
		lng: gate.lng + num(o.eastM) / (K * Math.cos((gate.lat * Math.PI) / 180)),
	};
}

function fixOf(gate: Gate, o: Obj): GateFix {
	return { ...position(gate, o), tMs: t0 + num(o.atS) * 1000, coveredM: num(o.coveredM) };
}

function optionsOf(o: unknown): GateCrossingOptions | undefined {
	if (o === null) return undefined;
	const p = o as Obj;
	return { maxGapS: num(p.maxGapS), maxHopM: num(p.maxHopM), rejectGapS: num(p.rejectGapS) };
}

function close(actual: number, expected: number, tol: number, what: string): void {
	assert.ok(Math.abs(actual - expected) <= tol, `${what}: ${actual} != ${expected} (tol ${tol})`);
}

function assertCrossing(actual: GateCrossing, e: Obj, where: string): void {
	assert.equal(actual.direction, e.direction, `${where} direction`);
	assert.equal(actual.gapped, e.gapped, `${where} gapped`);
	close(actual.fraction, num(e.fraction), fracTol, `${where} fraction`);
	close((actual.tMs - t0) / 1000, num(e.atS), timeTol, `${where} atS`);
	close(actual.coveredM, num(e.coveredM), distTol, `${where} coveredM`);
	close(actual.offsetM, num(e.offsetM), distTol, `${where} offsetM`);
}

test('every section in the file is one this reader runs', () => {
	const unknown = Object.keys(fixture).filter((k) => !META.has(k) && !SECTIONS.includes(k));
	assert.deepEqual(unknown, []);
	const schemaSections = Object.keys(fixture.schema as Obj).filter(
		(k) => !['general', 'constants', 'gate', 'position'].includes(k),
	);
	assert.deepEqual(new Set(schemaSections), new Set(SECTIONS));
	for (const s of SECTIONS) assert.ok(section(s).length > 0, `section ${s} is empty`);
});

test('the constants match the file', () => {
	assert.equal(GATE_EARTH_RADIUS_M, num(constants.EARTH_RADIUS_M));
	assert.equal(GATE_MAX_GAP_S, num(constants.MAX_GAP_S));
	assert.equal(GATE_MAX_HOP_M, num(constants.MAX_HOP_M));
	assert.equal(GATE_REJECT_GAP_S, num(constants.REJECT_GAP_S));
	assert.equal(GATE_HALF_WIDTH_RACE_M, num(constants.HALF_WIDTH_RACE_M));
	assert.equal(GATE_HALF_WIDTH_SEGMENT_M, num(constants.HALF_WIDTH_SEGMENT_M));
});

for (const c of section('projection')) {
	test(`projection: ${String(c.name)}`, () => {
		const gate = gateOf(c.gate as Obj);
		const p = position(gate, c.point as Obj);
		const got = gateProjection(gate, p.lat, p.lng);
		const e = c.expect as Obj;
		close(got.s, num(e.s), distTol, 's');
		close(got.u, num(e.u), distTol, 'u');
	});
}

for (const c of section('crossings')) {
	test(`crossings: ${String(c.name)}`, () => {
		const gate = gateOf(c.gate as Obj);
		const options = optionsOf(req(c, 'options'));
		const fixes = (c.fixes as Obj[]).map((f) => fixOf(gate, f));
		const expected = c.expect as Obj[];

		const detector = new GateCrossingDetector(gate, options);
		fixes.forEach((fix, i) => {
			const got = detector.offer(fix);
			const e = expected.find((x) => num(x.afterFix) === i);
			if (e === undefined) {
				assert.equal(got, null, `offer(fixes[${i}]) should return null`);
			} else {
				assert.ok(got !== null, `offer(fixes[${i}]) should return a crossing`);
				assertCrossing(got, e, `offer(fixes[${i}])`);
			}
		});

		const settled = detector.settle();
		assert.equal(settled.length, expected.length, 'settle() count');
		settled.forEach((x, i) => assertCrossing(x, expected[i], `settle()[${i}]`));

		const after = req(c, 'fixesAfterSettle') as Obj[] | null;
		for (const f of after ?? []) {
			assert.equal(detector.offer(fixOf(gate, f)), null, 'offer after settle');
		}
		assert.equal(detector.settle().length, expected.length, 'settle() unchanged');

		const batch = crossingsOf(fixes, gate, options);
		assert.equal(batch.length, expected.length, 'crossingsOf count');
		batch.forEach((x, i) => assertCrossing(x, expected[i], `crossingsOf[${i}]`));
	});
}
