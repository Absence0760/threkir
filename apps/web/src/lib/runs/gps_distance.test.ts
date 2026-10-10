import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as gps from './gps_distance';
import { GpsDistanceEstimator, SPEC_VERSION, smoothDistance, type GpsEvent } from './gps_distance';

// Replays the golden vectors every port of the GPS distance estimator shares
// (docs/features/gps_distance.md § Ports). The Dart half of the pair is
// packages/run_recorder/test/gps_distance_estimator_test.dart.

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE_PATH = join(__dirname, '..', '..', '..', '..', '..', 'fixtures', 'gps_distance_vectors.json');

type FixEvent = {
	type: 'fix';
	t: number;
	lat: number;
	lng: number;
	acc: number | null;
	speed: number | null;
	speedAcc: number | null;
	bearing: number | null;
};
type StepsEvent = { type: 'steps'; t: number; count: number | null };
type FinishEvent = { type: 'finish'; t: number };
type Scenario = {
	name: string;
	maxSpeedMps: number;
	expectedIntervalS: number;
	initialStrideM: number | null;
	events: Array<FixEvent | StepsEvent | FinishEvent>;
	expected: {
		distanceAfterEachEventM: number[];
		gpsDistanceM: number;
		stepDistanceM: number;
		strideM: number | null;
		rejectedFixes: number;
		zuptFixes: number;
		rScale: number;
		dopplerTrusted: boolean;
		dopplerScale: number;
	};
	smoothed: {
		distanceAfterEachEventM: number[];
		distanceM: number;
		gpsDistanceM: number;
		stepDistanceM: number;
		stoppedFixes: number;
		positions: Array<[number, number] | null>;
	};
};
type Fixture = {
	spec: string;
	tolerance_m: number;
	position_tolerance_deg: number;
	constants: Record<string, number>;
	scenarios: Scenario[];
};

const fixture = JSON.parse(readFileSync(FIXTURE_PATH, 'utf-8')) as Fixture;
const TOL = fixture.tolerance_m;
const POS_TOL = fixture.position_tolerance_deg;

function replay(s: Scenario): { est: GpsDistanceEstimator; after: number[] } {
	const est = new GpsDistanceEstimator(s.maxSpeedMps, s.expectedIntervalS, s.initialStrideM);
	const after: number[] = [];
	for (const e of s.events) {
		if (e.type === 'fix') est.addFix(e.t, e.lat, e.lng, e.acc, e.speed, e.speedAcc, e.bearing);
		else if (e.type === 'steps') est.addSteps(e.t, e.count);
		else est.finish(e.t);
		after.push(est.distanceM);
	}
	return { est, after };
}

test('fixture is spec v1.3 with a non-trivial scenario set', () => {
	assert.equal(fixture.spec, 'gps-distance-estimator v1.3');
	assert.equal(SPEC_VERSION, '1.3');
	assert.ok(fixture.scenarios.length >= 29, `only ${fixture.scenarios.length} scenarios`);
	assert.ok(TOL > 0 && TOL <= 0.001);
	assert.ok(POS_TOL > 0 && POS_TOL <= 1e-8);
});

test('every fixture constant matches the port', () => {
	const port = gps as unknown as Record<string, unknown>;
	for (const [name, value] of Object.entries(fixture.constants)) {
		assert.equal(port[name], value, `constant ${name}`);
	}
});

for (const s of fixture.scenarios) {
	test(`vector ${s.name}: distance after every event`, () => {
		const { after } = replay(s);
		assert.equal(after.length, s.expected.distanceAfterEachEventM.length);
		after.forEach((got, i) => {
			const want = s.expected.distanceAfterEachEventM[i];
			assert.ok(Math.abs(got - want) <= TOL, `${s.name} event ${i}: got ${got}, want ${want}`);
		});
	});

	test(`vector ${s.name}: final gps / step distance and stride`, () => {
		const { est } = replay(s);
		assert.ok(Math.abs(est.gpsDistanceM - s.expected.gpsDistanceM) <= TOL, `gps ${est.gpsDistanceM}`);
		assert.ok(
			Math.abs(est.stepDistanceM - s.expected.stepDistanceM) <= TOL,
			`steps ${est.stepDistanceM}`,
		);
		if (s.expected.strideM === null) {
			assert.equal(est.strideM, null);
		} else {
			assert.notEqual(est.strideM, null);
			assert.ok(Math.abs((est.strideM as number) - s.expected.strideM) <= TOL, `stride ${est.strideM}`);
		}
	});

	test(`vector ${s.name}: gate, zupt, adaptive R, cross-check and Doppler scale diagnostics`, () => {
		const { est } = replay(s);
		assert.equal(est.rejectedFixes, s.expected.rejectedFixes);
		assert.equal(est.zuptFixes, s.expected.zuptFixes);
		assert.equal(est.dopplerTrusted, s.expected.dopplerTrusted);
		assert.ok(Math.abs(est.rScale - s.expected.rScale) <= 1e-6, `rScale ${est.rScale}`);
		assert.ok(
			Math.abs(est.dopplerScale - s.expected.dopplerScale) <= 1e-6,
			`dopplerScale ${est.dopplerScale}`,
		);
	});

	test(`vector ${s.name}: smoothed distance and positions`, () => {
		const sm = smoothDistance(s.events as GpsEvent[], s.maxSpeedMps, s.expectedIntervalS, s.initialStrideM);
		const want = s.smoothed;
		assert.equal(sm.cumulativeM.length, want.distanceAfterEachEventM.length);
		sm.cumulativeM.forEach((got, i) => {
			const w = want.distanceAfterEachEventM[i];
			assert.ok(Math.abs(got - w) <= TOL, `${s.name} smoothed event ${i}: got ${got}, want ${w}`);
		});
		assert.ok(Math.abs(sm.distanceM - want.distanceM) <= TOL, `distance ${sm.distanceM}`);
		assert.ok(Math.abs(sm.gpsDistanceM - want.gpsDistanceM) <= TOL, `gps ${sm.gpsDistanceM}`);
		assert.ok(Math.abs(sm.stepDistanceM - want.stepDistanceM) <= TOL, `steps ${sm.stepDistanceM}`);
		assert.equal(sm.stoppedFixes, want.stoppedFixes);
		assert.equal(sm.positions.length, want.positions.length);
		sm.positions.forEach((got, i) => {
			const w = want.positions[i];
			if (w === null) {
				assert.equal(got, null, `${s.name} position ${i}`);
				return;
			}
			assert.notEqual(got, null, `${s.name} position ${i}`);
			const [lat, lng] = got as [number, number];
			assert.ok(Math.abs(lat - w[0]) <= POS_TOL, `${s.name} lat ${i}: got ${lat}, want ${w[0]}`);
			assert.ok(Math.abs(lng - w[1]) <= POS_TOL, `${s.name} lng ${i}: got ${lng}, want ${w[1]}`);
		});
	});
}

test('a fix with a non-finite timestamp or coordinate credits nothing', () => {
	const est = new GpsDistanceEstimator();
	assert.equal(est.addFix(Number.NaN, 40, -75), 0);
	assert.equal(est.addFix(0, Number.NaN, -75), 0);
	assert.equal(est.addFix(0, 40, Number.POSITIVE_INFINITY), 0);
	assert.equal(est.addFix(null, 40, -75), 0);
	assert.equal(est.distanceM, 0);
});

test('a gap over GAP_S re-anchors and credits nothing for the jump', () => {
	const est = new GpsDistanceEstimator();
	est.addFix(0, 40, -75, 3, 3, 0.3, 0);
	est.addFix(1, 40.000027, -75, 3, 3, 0.3, 0);
	const before = est.distanceM;
	// ~1.1 km north, 30 s later: a re-anchor, not a 37 m/s sprint.
	assert.equal(est.addFix(31, 40.01, -75, 3, 3, 0.3, 0), 0);
	assert.equal(est.distanceM, before);
});

test('finish with no pending steps and no fixes is a no-op', () => {
	const est = new GpsDistanceEstimator();
	est.finish(100);
	assert.equal(est.distanceM, 0);
	assert.equal(est.strideM, null);
});

test('a non-finite or sub-second interval hint behaves as 1 s', () => {
	for (const it of [Number.NaN, Number.POSITIVE_INFINITY, 0.5, -3]) {
		const est = new GpsDistanceEstimator(10, it);
		est.addFix(0, 40, -75);
		est.addFix(11, 40.0003, -75);
		assert.equal(est.gpsDistanceM, 0, `interval ${it}`);
	}
});

test('initial stride is kept only when finite and in range', () => {
	assert.equal(new GpsDistanceEstimator(10, 1, 1.1).strideM, 1.1);
	assert.equal(new GpsDistanceEstimator(10, 1, 0.3).strideM, null);
	assert.equal(new GpsDistanceEstimator(10, 1, 2.6).strideM, null);
	assert.equal(new GpsDistanceEstimator(10, 1, Number.NaN).strideM, null);
});
