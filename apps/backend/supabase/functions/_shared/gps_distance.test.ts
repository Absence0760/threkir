import { assert, assertEquals, assertNotEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import * as gps from './gps_distance.ts';
import { GpsDistanceEstimator, SPEC_VERSION, smoothDistance, type GpsEvent } from './gps_distance.ts';

// The Deno copy of the estimator replays the same golden vectors as every
// other port (docs/features/gps_distance.md § Ports).

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

const fixture = JSON.parse(
	await Deno.readTextFile(new URL('../../../../../fixtures/gps_distance_vectors.json', import.meta.url)),
) as Fixture;
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

Deno.test('the port implements the spec v1.2 fixture: version, scenario set and every constant', () => {
	assertEquals(fixture.spec, 'gps-distance-estimator v1.2');
	assertEquals(SPEC_VERSION, '1.2');
	assert(fixture.scenarios.length >= 27, `only ${fixture.scenarios.length} scenarios`);
	assert(TOL > 0 && TOL <= 0.001);
	assert(POS_TOL > 0 && POS_TOL <= 1e-8);
	const port = gps as unknown as Record<string, unknown>;
	for (const [name, value] of Object.entries(fixture.constants)) {
		assertEquals(port[name], value, `constant ${name}`);
	}
});

for (const s of fixture.scenarios) {
	Deno.test(`vector ${s.name}: distance after every event`, () => {
		const { after } = replay(s);
		assertEquals(after.length, s.expected.distanceAfterEachEventM.length);
		after.forEach((got, i) => {
			const want = s.expected.distanceAfterEachEventM[i];
			assert(Math.abs(got - want) <= TOL, `${s.name} event ${i}: got ${got}, want ${want}`);
		});
	});

	Deno.test(`vector ${s.name}: final gps / step distance and stride`, () => {
		const { est } = replay(s);
		assert(Math.abs(est.gpsDistanceM - s.expected.gpsDistanceM) <= TOL, `gps ${est.gpsDistanceM}`);
		assert(
			Math.abs(est.stepDistanceM - s.expected.stepDistanceM) <= TOL,
			`steps ${est.stepDistanceM}`,
		);
		if (s.expected.strideM === null) {
			assertEquals(est.strideM, null);
		} else {
			assertNotEquals(est.strideM, null);
			assert(Math.abs((est.strideM as number) - s.expected.strideM) <= TOL, `stride ${est.strideM}`);
		}
	});

	Deno.test(`vector ${s.name}: gate, zupt, adaptive R and cross-check diagnostics`, () => {
		const { est } = replay(s);
		assertEquals(est.rejectedFixes, s.expected.rejectedFixes);
		assertEquals(est.zuptFixes, s.expected.zuptFixes);
		assertEquals(est.dopplerTrusted, s.expected.dopplerTrusted);
		assert(Math.abs(est.rScale - s.expected.rScale) <= 1e-6, `rScale ${est.rScale}`);
	});

	Deno.test(`vector ${s.name}: smoothed distance and positions`, () => {
		const sm = smoothDistance(s.events as GpsEvent[], s.maxSpeedMps, s.expectedIntervalS, s.initialStrideM);
		const want = s.smoothed;
		assertEquals(sm.cumulativeM.length, want.distanceAfterEachEventM.length);
		sm.cumulativeM.forEach((got, i) => {
			const w = want.distanceAfterEachEventM[i];
			assert(Math.abs(got - w) <= TOL, `${s.name} smoothed event ${i}: got ${got}, want ${w}`);
		});
		assert(Math.abs(sm.distanceM - want.distanceM) <= TOL, `distance ${sm.distanceM}`);
		assert(Math.abs(sm.gpsDistanceM - want.gpsDistanceM) <= TOL, `gps ${sm.gpsDistanceM}`);
		assert(Math.abs(sm.stepDistanceM - want.stepDistanceM) <= TOL, `steps ${sm.stepDistanceM}`);
		assertEquals(sm.stoppedFixes, want.stoppedFixes);
		assertEquals(sm.positions.length, want.positions.length);
		sm.positions.forEach((got, i) => {
			const w = want.positions[i];
			if (w === null) {
				assertEquals(got, null, `${s.name} position ${i}`);
				return;
			}
			assertNotEquals(got, null, `${s.name} position ${i}`);
			const [lat, lng] = got as [number, number];
			assert(Math.abs(lat - w[0]) <= POS_TOL, `${s.name} lat ${i}: got ${lat}, want ${w[0]}`);
			assert(Math.abs(lng - w[1]) <= POS_TOL, `${s.name} lng ${i}: got ${lng}, want ${w[1]}`);
		});
	});
}

Deno.test('a fix with a non-finite timestamp or coordinate credits nothing', () => {
	const est = new GpsDistanceEstimator();
	assertEquals(est.addFix(Number.NaN, 40, -75), 0);
	assertEquals(est.addFix(0, Number.NaN, -75), 0);
	assertEquals(est.addFix(0, 40, Number.POSITIVE_INFINITY), 0);
	assertEquals(est.addFix(null, 40, -75), 0);
	assertEquals(est.distanceM, 0);
});

Deno.test('a gap over GAP_S re-anchors and credits nothing for the jump', () => {
	const est = new GpsDistanceEstimator();
	est.addFix(0, 40, -75, 3, 3, 0.3, 0);
	est.addFix(1, 40.000027, -75, 3, 3, 0.3, 0);
	const before = est.distanceM;
	// ~1.1 km north, 30 s later: a re-anchor, not a 37 m/s sprint.
	assertEquals(est.addFix(31, 40.01, -75, 3, 3, 0.3, 0), 0);
	assertEquals(est.distanceM, before);
});

Deno.test('finish with no pending steps and no fixes is a no-op', () => {
	const est = new GpsDistanceEstimator();
	est.finish(100);
	assertEquals(est.distanceM, 0);
	assertEquals(est.strideM, null);
});

Deno.test('a non-finite or sub-second interval hint behaves as 1 s', () => {
	for (const it of [Number.NaN, Number.POSITIVE_INFINITY, 0.5, -3]) {
		const est = new GpsDistanceEstimator(10, it);
		est.addFix(0, 40, -75);
		est.addFix(11, 40.0003, -75);
		assertEquals(est.gpsDistanceM, 0, `interval ${it}`);
	}
});

Deno.test('initial stride is kept only when finite and in range', () => {
	assertEquals(new GpsDistanceEstimator(10, 1, 1.1).strideM, 1.1);
	assertEquals(new GpsDistanceEstimator(10, 1, 0.3).strideM, null);
	assertEquals(new GpsDistanceEstimator(10, 1, 2.6).strideM, null);
	assertEquals(new GpsDistanceEstimator(10, 1, Number.NaN).strideM, null);
});
