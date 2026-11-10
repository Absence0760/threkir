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
	learnStride: boolean;
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
	const est = new GpsDistanceEstimator(
		s.maxSpeedMps,
		s.expectedIntervalS,
		s.initialStrideM,
		false,
		s.learnStride,
	);
	const after: number[] = [];
	for (const e of s.events) {
		if (e.type === 'fix') est.addFix(e.t, e.lat, e.lng, e.acc, e.speed, e.speedAcc, e.bearing);
		else if (e.type === 'steps') est.addSteps(e.t, e.count);
		else est.finish(e.t);
		after.push(est.distanceM);
	}
	return { est, after };
}

test('fixture is spec v1.6 with a non-trivial scenario set', () => {
	assert.equal(fixture.spec, 'gps-distance-estimator v1.6');
	assert.equal(SPEC_VERSION, '1.6');
	assert.ok(fixture.scenarios.length >= 49, `only ${fixture.scenarios.length} scenarios`);
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
		const sm = smoothDistance(
			s.events as GpsEvent[],
			s.maxSpeedMps,
			s.expectedIntervalS,
			s.initialStrideM,
			s.learnStride,
		);
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

test('a gap over GAP_S re-anchors and credits the chord, capped at maxSpeed x dt (v1.4)', () => {
	const est = new GpsDistanceEstimator();
	est.addFix(0, 40, -75, 3, 3, 0.3, 0);
	est.addFix(1, 40.000027, -75, 3, 3, 0.3, 0);
	const before = est.distanceM;
	// ~1.1 km north, 30 s later: a re-anchor, not a 37 m/s sprint, so the
	// chord is credited only up to the 10 m/s ceiling over the 30 s.
	assert.equal(est.addFix(31, 40.01, -75, 3, 3, 0.3, 0), 300);
	assert.equal(est.distanceM, before + 300);
});

test('a reachable gap credits its chord less the 1-sigma uncertainty of both ends (v1.4)', () => {
	const est = new GpsDistanceEstimator();
	est.addFix(0, 40, -75, 3, 3, 0.3, 0);
	est.addFix(1, 40.000027, -75, 3, 3, 0.3, 0);
	// ~97 m north, 30 s later: the straight line across the gap is a lower
	// bound on the path, less sqrt(ax + ay + 2r). Value from reference.py.
	const credit = est.addFix(31, 40.0009, -75, 3, 3, 0.3, 0);
	assert.ok(Math.abs(credit - 91.887248) <= 1e-3, `credit ${credit}`);
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
		// An 11 s interval is a gap at 1 s, credited only by its chord less the
		// 1-sigma uncertainty of both ends: sqrt(9 + 9 + 2 * 9) = 6 m.
		const chord = ((0.0003 * Math.PI) / 180) * gps.EARTH_RADIUS_M;
		assert.ok(Math.abs(est.gpsDistanceM - (chord - 6)) < 1e-6, `interval ${it}`);
	}
});

test('initial stride is kept only when finite and in range', () => {
	assert.equal(new GpsDistanceEstimator(10, 1, 1.1).strideM, 1.1);
	assert.equal(new GpsDistanceEstimator(10, 1, 0.3).strideM, null);
	assert.equal(new GpsDistanceEstimator(10, 1, 2.6).strideM, null);
	assert.equal(new GpsDistanceEstimator(10, 1, Number.NaN).strideM, null);
});

test('a fix stating worse than MAX_POS_SIGMA_M is ignored outright', () => {
	const est = new GpsDistanceEstimator();
	assert.equal(est.addFix(0, 40, -75, 51), 0);
	est.addFix(1, 40, -75, 50);
	est.addFix(2, 40.00003, -75, 51, 3, 0.3, 0);
	assert.equal(est.distanceM, 0);
});

test('learnStride false never learns a stride, and keeps a seeded one', () => {
	for (const seed of [null, 0.95]) {
		const est = new GpsDistanceEstimator(10, 1, seed, false, false);
		for (let i = 0; i < 120; i++) {
			est.addFix(i, 40 + i * 0.000025, -75, 4, 2.78, 0.3, 0);
			est.addSteps(i + 0.5, (i + 1) * 3);
		}
		assert.equal(est.strideM, seed);
	}
});

test('the ZUPT window stretches to the step batches walking delivers (v1.5)', () => {
	const est = new GpsDistanceEstimator();
	est.addSteps(0, 0);
	est.addSteps(1, 2);
	est.addSteps(16, 29);
	assert.equal(est.stepBatchS, 15);
	assert.equal(est.zuptWindowS, 22.5);
	est.addSteps(41, 72);
	assert.equal(est.zuptWindowS, gps.ZUPT_MAX_NO_STEP_S);
});

test('a stop then a few steps is not a batch, so the window stays put (v1.5)', () => {
	const est = new GpsDistanceEstimator();
	est.addSteps(0, 0);
	est.addSteps(1, 2);
	est.addSteps(2, 4);
	est.addSteps(62, 8);
	assert.equal(est.stepBatchS, 1);
	assert.equal(est.zuptWindowS, gps.ZUPT_NO_STEP_S);
});

test('a fused pocket walk with 15 s step batches is not read as stopped (v1.5)', () => {
	const est = new GpsDistanceEstimator(5, 1, 0.72, false, false);
	for (let i = 0; i < 300; i++) {
		est.addFix(i, 40 + (i * 1.3) / 111195, -75, 4);
		if ((i + 1) % 15 === 0) est.addSteps(i + 0.5, Math.floor((i + 1) * 1.8));
	}
	assert.ok(est.zuptFixes <= 9, `zuptFixes ${est.zuptFixes}`);
	assert.ok(Math.abs(est.distanceM - 390) <= 390 * 0.05, `distance ${est.distanceM}`);
});

const EAST_M_PER_DEG = 111195 * Math.cos((40 * Math.PI) / 180);

function eastward(): GpsDistanceEstimator {
	const est = new GpsDistanceEstimator(10, 1, 0.5, false, false);
	for (let i = 0; i <= 25; i++) {
		est.addFix(i, 40, -75 + (4 * i) / EAST_M_PER_DEG, 3, 4, 0.3, 90);
		est.addSteps(i + 0.5, 4 * i + 2);
	}
	return est;
}

test('a late step batch tops a gap up without counting its chord twice (v1.6)', () => {
	// Steps at 0.5 m credit 2 m/s, so the straight 30 s gap's 116 m chord
	// lower bound wins. The batch after the resuming fix moves 10 m of that
	// credit from the chord to the steps and adds nothing.
	const est = eastward();
	est.addSteps(50, 202);
	est.addFix(55, 40, -75 + 220 / EAST_M_PER_DEG, 3, 4, 0.3, 90);
	const before = est.distanceM;
	const steps = est.stepDistanceM;
	est.addSteps(56.5, 228);
	assert.ok(Math.abs(est.distanceM - before) < 1e-9, `distance ${est.distanceM}`);
	assert.ok(Math.abs(est.stepDistanceM - steps - 10) < 1e-9, `steps ${est.stepDistanceM}`);
});

test('a late sample stamped inside a gap shares only its own interval (v1.6)', () => {
	// 2 steps over (50, 51] at a 0.5 m stride credit 1 m; sharing the rest of
	// the gap, which the fix at 55 closed before the sample arrived, at the
	// sample's rate would credit 5 m.
	const est = eastward();
	est.addSteps(50, 202);
	est.addFix(55, 40, -75 + 110 / EAST_M_PER_DEG, 3, 4, 0.3, 90);
	const before = est.distanceM;
	const steps = est.stepDistanceM;
	est.addSteps(51, 204);
	assert.ok(Math.abs(est.distanceM - before - 1) < 1e-9, `distance ${est.distanceM}`);
	assert.ok(Math.abs(est.stepDistanceM - steps - 1) < 1e-9, `steps ${est.stepDistanceM}`);
});

test('a fix bridging a short stall teaches no stride from its credit (v1.6)', () => {
	// 4 m/s at 4 steps/s is a 1 m stride. The fix at 36 bridges a 7 s stall
	// whose samples emptied the window; feeding its 28 m to the window learns
	// 1.092 m, and letting the sample at 36.5 refill it 0.985 m.
	const est = new GpsDistanceEstimator();
	for (let i = 0; i <= 60; i++) {
		if (i < 30 || i >= 36) est.addFix(i, 40, -75 + (4 * i) / EAST_M_PER_DEG, 3, 4, 0.3, 90);
		est.addSteps(i + 0.5, 4 * i + 2);
	}
	assert.ok(Math.abs((est.strideM ?? 0) - 1) < 1e-9, `stride ${est.strideM}`);
});

test('a stretch credits no steps taken before its first fix (v1.6)', () => {
	const est = new GpsDistanceEstimator(10, 1, 1.0, false, false);
	for (let i = 0; i < 30; i++) est.addSteps(i + 0.5, 4 * i);
	est.addFix(30, 40, -75, 3);
	est.finish(31);
	assert.equal(est.distanceM, 0);
});
