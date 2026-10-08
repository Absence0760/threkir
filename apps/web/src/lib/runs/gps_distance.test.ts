import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as gps from './gps_distance';
import { GpsDistanceEstimator } from './gps_distance';

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
	};
};
type Fixture = {
	spec: string;
	tolerance_m: number;
	constants: Record<string, number>;
	scenarios: Scenario[];
};

const fixture = JSON.parse(readFileSync(FIXTURE_PATH, 'utf-8')) as Fixture;
const TOL = fixture.tolerance_m;

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

test('fixture is spec v1.1 with a non-trivial scenario set', () => {
	assert.equal(fixture.spec, 'gps-distance-estimator v1.1');
	assert.ok(fixture.scenarios.length >= 10, `only ${fixture.scenarios.length} scenarios`);
	assert.ok(TOL > 0 && TOL <= 0.001);
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
			assert.ok(Math.abs((est.strideM as number) - s.expected.strideM) <= 1e-5, `stride ${est.strideM}`);
		}
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
