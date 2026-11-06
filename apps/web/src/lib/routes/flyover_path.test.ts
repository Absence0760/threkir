import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	advance,
	buildFlyoverPath,
	cameraAt,
	DEFAULT_FLYOVER_SPEED_MPS,
	distanceMarkers,
	FLYOVER_SPEEDS,
	pointAtDistance,
	type PathPoint,
} from './flyover_path';
import { haversineMetres } from '../runs/run_stats';

const M_PER_DEG_LAT = 111320;

function p(lat: number, lng: number, ele: number | null = null): PathPoint {
	return { lat, lng, ele };
}

/** A straight line due north from (0, 0), `km` long, one point per 100 m. */
function northLine(km: number): PathPoint[] {
	const out: PathPoint[] = [];
	for (let m = 0; m <= km * 1000; m += 100) out.push(p(m / M_PER_DEG_LAT, 0, m / 10));
	return out;
}

function angleDiff(a: number, b: number): number {
	const d = Math.abs(a - b) % 360;
	return d > 180 ? 360 - d : d;
}

test('buildFlyoverPath on an empty input is an empty path', () => {
	const path = buildFlyoverPath([]);
	assert.deepEqual(path, { points: [], cumM: [], totalM: 0 });
});

test('buildFlyoverPath drops non-finite coordinates and nulls a non-finite elevation', () => {
	const path = buildFlyoverPath([
		p(0, 0, 10),
		p(Number.NaN, 0),
		p(0, Number.POSITIVE_INFINITY),
		p(0.001, 0, Number.NaN),
	]);
	assert.equal(path.points.length, 2);
	assert.equal(path.points[1].ele, null);
});

test('buildFlyoverPath drops consecutive duplicates but keeps a revisit', () => {
	const path = buildFlyoverPath([p(0, 0), p(0, 0), p(0.001, 0), p(0, 0)]);
	assert.equal(path.points.length, 3);
	assert.equal(path.cumM.length, 3);
	assert.ok(Math.abs(path.totalM - 2 * haversineMetres(0, 0, 0.001, 0)) < 1e-6);
});

test('a duplicate supplies the elevation its kept twin lacked', () => {
	const path = buildFlyoverPath([p(0, 0, null), p(0, 0, 42), p(0.001, 0, 50)]);
	assert.equal(path.points[0].ele, 42);
});

test('buildFlyoverPath does not mutate its input', () => {
	const input = [p(0, 0, null), p(0, 0, 42)];
	buildFlyoverPath(input);
	assert.equal(input[0].ele, null);
});

test('cumM is monotonic and ends at totalM', () => {
	const path = buildFlyoverPath(northLine(3));
	for (let i = 1; i < path.cumM.length; i++) assert.ok(path.cumM[i] > path.cumM[i - 1]);
	assert.equal(path.cumM[0], 0);
	assert.equal(path.cumM[path.cumM.length - 1], path.totalM);
	assert.ok(Math.abs(path.totalM - 3000) < 5);
});

test('pointAtDistance throws on an empty path rather than inventing a position', () => {
	assert.throws(() => pointAtDistance(buildFlyoverPath([]), 0), RangeError);
});

test('pointAtDistance on a single point returns it for any distance', () => {
	const path = buildFlyoverPath([p(51.5, -0.1, 12)]);
	for (const d of [0, 100, -5, Number.NaN, Number.POSITIVE_INFINITY]) {
		assert.deepEqual(pointAtDistance(path, d), { lat: 51.5, lng: -0.1, ele: 12, index: 0 });
	}
});

test('pointAtDistance interpolates within a segment and reports its start index', () => {
	const path = buildFlyoverPath([p(0, 0, 0), p(0.01, 0, 100), p(0.02, 0, 300)]);
	const half = path.cumM[1] / 2;
	const r = pointAtDistance(path, half);
	assert.equal(r.index, 0);
	assert.ok(Math.abs(r.lat - 0.005) < 1e-9);
	assert.ok(Math.abs((r.ele ?? 0) - 50) < 1e-9);
	const r2 = pointAtDistance(path, path.cumM[1] + (path.cumM[2] - path.cumM[1]) / 4);
	assert.equal(r2.index, 1);
	assert.ok(Math.abs((r2.ele ?? 0) - 150) < 1e-9);
});

test('pointAtDistance lands exactly on vertices', () => {
	const path = buildFlyoverPath([p(0, 0, 1), p(0.01, 0, 2), p(0.02, 0, 3)]);
	assert.deepEqual(pointAtDistance(path, path.cumM[1]), { lat: 0.01, lng: 0, ele: 2, index: 1 });
	assert.deepEqual(pointAtDistance(path, 0), { lat: 0, lng: 0, ele: 1, index: 0 });
});

test('pointAtDistance clamps past either end and treats NaN as the start', () => {
	const path = buildFlyoverPath([p(0, 0, 1), p(0.01, 0, 2)]);
	assert.deepEqual(pointAtDistance(path, -50), { lat: 0, lng: 0, ele: 1, index: 0 });
	assert.deepEqual(pointAtDistance(path, 1e9), { lat: 0.01, lng: 0, ele: 2, index: 1 });
	assert.deepEqual(pointAtDistance(path, Number.POSITIVE_INFINITY), { lat: 0.01, lng: 0, ele: 2, index: 1 });
	assert.deepEqual(pointAtDistance(path, Number.NEGATIVE_INFINITY), { lat: 0, lng: 0, ele: 1, index: 0 });
	assert.deepEqual(pointAtDistance(path, Number.NaN), { lat: 0, lng: 0, ele: 1, index: 0 });
});

test('interpolated elevation falls back to the known side when one end is null', () => {
	const path = buildFlyoverPath([p(0, 0, null), p(0.01, 0, 80), p(0.02, 0, null), p(0.03, 0, null)]);
	assert.equal(pointAtDistance(path, path.cumM[1] / 2).ele, 80);
	assert.equal(pointAtDistance(path, (path.cumM[1] + path.cumM[2]) / 2).ele, 80);
	assert.equal(pointAtDistance(path, (path.cumM[2] + path.cumM[3]) / 2).ele, null);
});

test('pointAtDistance interpolates across the antimeridian the short way', () => {
	const path = buildFlyoverPath([p(0, 179.999), p(0, -179.999)]);
	assert.ok(path.totalM < 300);
	const mid = pointAtDistance(path, path.totalM / 2);
	assert.ok(Math.abs(Math.abs(mid.lng) - 180) < 1e-9);
});

test('cameraAt looks due north along a northbound line', () => {
	const path = buildFlyoverPath(northLine(2));
	const pose = cameraAt(path, 500);
	assert.ok(angleDiff(pose.bearing, 0) < 1e-6);
	assert.equal(pose.center[0], 0);
	assert.ok(Math.abs(pose.center[1] * M_PER_DEG_LAT - 500) < 2);
	assert.ok(Math.abs((pose.lookAt[1] - pose.center[1]) * M_PER_DEG_LAT - 300) < 2);
});

test('cameraAt bearing is in [0, 360) for every compass direction', () => {
	for (const deg of [0, 45, 90, 135, 180, 225, 270, 315, 359]) {
		const r = (deg * Math.PI) / 180;
		const path = buildFlyoverPath([p(0, 0), p(Math.cos(r) * 0.01, Math.sin(r) * 0.01)]);
		const { bearing } = cameraAt(path, path.totalM / 2);
		assert.ok(bearing >= 0 && bearing < 360, `${deg} -> ${bearing}`);
		assert.ok(angleDiff(bearing, deg) < 0.5, `${deg} -> ${bearing}`);
	}
});

test('smoothing averages 359 and 1 to north, not south', () => {
	const r359 = (359 * Math.PI) / 180;
	const r1 = (1 * Math.PI) / 180;
	const a = p(0, 0);
	const b = p(Math.cos(r359) * 0.002, Math.sin(r359) * 0.002);
	const c = p(b.lat + Math.cos(r1) * 0.002, b.lng + Math.sin(r1) * 0.002);
	const path = buildFlyoverPath([a, b, c]);
	const { bearing } = cameraAt(path, path.cumM[1], { smoothingM: 200 });
	assert.ok(angleDiff(bearing, 0) < 0.1, `got ${bearing}`);
});

test('a short sideways jog inside the smoothing window does not whip the camera', () => {
	const pts: PathPoint[] = [];
	for (let m = 0; m <= 1000; m += 50) pts.push(p(m / M_PER_DEG_LAT, 0));
	const jog = 30 / M_PER_DEG_LAT;
	for (let m = 1000; m <= 2000; m += 50) pts.push(p(m / M_PER_DEG_LAT, jog));
	const path = buildFlyoverPath(pts);
	const inJog = path.cumM[20] + 15;
	const raw = cameraAt(path, inJog, { smoothingM: 0 }).bearing;
	assert.ok(angleDiff(raw, 90) < 0.5, `raw ${raw}`);
	const smoothed = cameraAt(path, inJog).bearing;
	assert.ok(angleDiff(smoothed, 0) < 6, `smoothed ${smoothed}`);
});

test('cameraAt is deterministic', () => {
	const path = buildFlyoverPath(northLine(5));
	assert.deepEqual(cameraAt(path, 1234.5), cameraAt(path, 1234.5));
});

test('cameraAt clamps the look-ahead at the finish and keeps the last heading', () => {
	const path = buildFlyoverPath(northLine(1));
	const pose = cameraAt(path, path.totalM);
	assert.deepEqual(pose.lookAt, pose.center);
	assert.ok(angleDiff(pose.bearing, 0) < 1e-6);
	const near = cameraAt(path, path.totalM - 100);
	const last = path.points[path.points.length - 1];
	assert.deepEqual(near.lookAt, [last.lng, last.lat]);
	assert.deepEqual(cameraAt(path, 1e12), pose);
});

test('cameraAt with zero smoothing uses the heading of the segment under the camera', () => {
	const path = buildFlyoverPath([p(0, 0), p(0.01, 0), p(0.01, 0.01)]);
	assert.ok(angleDiff(cameraAt(path, path.cumM[1] / 2, { smoothingM: 0 }).bearing, 0) < 1e-6);
	const eastward = cameraAt(path, (path.cumM[1] + path.totalM) / 2, { smoothingM: 0 });
	assert.ok(angleDiff(eastward.bearing, 90) < 0.01);
});

test('cameraAt treats non-finite and negative options as defaults or zero', () => {
	const path = buildFlyoverPath(northLine(2));
	const def = cameraAt(path, 500);
	assert.deepEqual(cameraAt(path, 500, { lookAheadM: Number.NaN, smoothingM: Number.POSITIVE_INFINITY }), def);
	const zero = cameraAt(path, 500, { lookAheadM: -10 });
	assert.deepEqual(zero.lookAt, zero.center);
});

test('cameraAt on a single point is a still camera facing north', () => {
	const pose = cameraAt(buildFlyoverPath([p(10, 20)]), 0);
	assert.deepEqual(pose, { center: [20, 10], bearing: 0, lookAt: [20, 10] });
});

test('cameraAt on an exact out-and-back reversal still yields a finite bearing', () => {
	const path = buildFlyoverPath([p(0, 0), p(0.001, 0), p(0, 0)]);
	const { bearing } = cameraAt(path, path.cumM[1]);
	assert.ok(Number.isFinite(bearing) && bearing >= 0 && bearing < 360);
});

/** 3 km north, a hairpin `gapM` east, 3 km back south: an out-and-back course's turnaround. */
function outAndBack(gapM: number): { path: ReturnType<typeof buildFlyoverPath>; turnM: number } {
	const pts: PathPoint[] = [];
	for (let m = 0; m <= 3000; m += 10) pts.push(p(m / M_PER_DEG_LAT, 0));
	const east = gapM / M_PER_DEG_LAT;
	for (let m = 3000; m >= 0; m -= 10) pts.push(p(m / M_PER_DEG_LAT, east));
	const path = buildFlyoverPath(pts);
	return { path, turnM: path.cumM[300] };
}

for (const gapM of [0, 15]) {
	test(`the camera swings round an out-and-back turnaround (${gapM} m wide) instead of flipping`, () => {
		const { path, turnM } = outAndBack(gapM);
		let prev = cameraAt(path, turnM - 800).bearing;
		let worstPerMetre = 0;
		for (let d = turnM - 800; d <= turnM + 800; d += 1) {
			const b = cameraAt(path, d).bearing;
			worstPerMetre = Math.max(worstPerMetre, angleDiff(b, prev));
			prev = b;
		}
		assert.ok(worstPerMetre <= 0.61, `turned ${worstPerMetre.toFixed(1)} deg in one metre`);
		const frameM = 1000 / 60;
		for (let d = turnM - 800; d <= turnM + 800; d += frameM) {
			const step = angleDiff(cameraAt(path, d).bearing, cameraAt(path, d + frameM).bearing);
			assert.ok(step <= 10.5, `turned ${step.toFixed(1)} deg in one 60 fps frame at 1000 m/s`);
		}
		assert.ok(angleDiff(cameraAt(path, turnM - 800).bearing, 0) < 0.5);
		assert.ok(angleDiff(cameraAt(path, turnM + 800).bearing, 180) < 0.5);
		assert.ok(angleDiff(cameraAt(path, turnM).bearing, 90) < 15, 'faces across the turn at the turnaround');
	});
}

test('an ordinary 90 degree corner is not slowed by the turn limit', () => {
	const pts: PathPoint[] = [];
	for (let m = 0; m <= 2000; m += 10) pts.push(p(m / M_PER_DEG_LAT, 0));
	for (let m = 10; m <= 2000; m += 10) pts.push(p(2000 / M_PER_DEG_LAT, m / M_PER_DEG_LAT));
	const path = buildFlyoverPath(pts);
	const corner = path.cumM[200];
	assert.ok(angleDiff(cameraAt(path, corner).bearing, 45) < 1);
	assert.ok(angleDiff(cameraAt(path, corner + 250).bearing, 90) < 0.5);
});

test('the turnaround bearing is the same however the flight reaches it', () => {
	const { path, turnM } = outAndBack(15);
	const scrubbed = cameraAt(path, turnM + 37.5).bearing;
	const fresh = cameraAt(outAndBack(15).path, turnM + 37.5).bearing;
	for (let d = 0; d < turnM; d += 250) cameraAt(path, d);
	assert.equal(cameraAt(path, turnM + 37.5).bearing, scrubbed);
	assert.equal(fresh, scrubbed);
});

test('cameraAt across the antimeridian heads east, not west', () => {
	const path = buildFlyoverPath([p(0, 179.99), p(0, -179.99)]);
	assert.ok(angleDiff(cameraAt(path, path.totalM / 2).bearing, 90) < 0.01);
});

test('distanceMarkers every whole km, excluding 0', () => {
	const path = buildFlyoverPath(northLine(5.5));
	const markers = distanceMarkers(path, 'km');
	assert.deepEqual(markers.map((m) => m.label), [1, 2, 3, 4, 5]);
	assert.deepEqual(markers.map((m) => m.dM), [1000, 2000, 3000, 4000, 5000]);
	for (const m of markers) {
		const pt = pointAtDistance(path, m.dM);
		assert.equal(m.lat, pt.lat);
		assert.equal(m.lng, pt.lng);
	}
});

test('distanceMarkers in miles step 1609.344 m', () => {
	const path = buildFlyoverPath(northLine(5.5));
	const markers = distanceMarkers(path, 'mi');
	assert.deepEqual(markers.map((m) => m.label), [1, 2, 3]);
	assert.deepEqual(markers.map((m) => m.dM), [1609.344, 3218.688, 4828.032]);
});

test('a course a hair short of a whole km by float error still gets its final marker', () => {
	const path = buildFlyoverPath(northLine(1));
	const shaved = { ...path, totalM: 1000 - 1e-7 };
	assert.deepEqual(distanceMarkers(shaved, 'km').map((m) => m.label), [1]);
	assert.ok(distanceMarkers(shaved, 'km')[0].dM <= shaved.totalM);
});

test('distanceMarkers with an official distance place each km on the scaled line', () => {
	const path = buildFlyoverPath(northLine(5.5));
	const markers = distanceMarkers(path, 'km', 5000);
	assert.deepEqual(markers.map((m) => m.label), [1, 2, 3, 4, 5]);
	markers.forEach((m, i) => assert.ok(Math.abs(m.dM - ((i + 1) * 1000 * path.totalM) / 5000) < 1e-6));
	assert.ok(markers[4].dM <= path.totalM);
});

test('distanceMarkers on a short, single-point or empty path is empty', () => {
	assert.deepEqual(distanceMarkers(buildFlyoverPath([]), 'km'), []);
	assert.deepEqual(distanceMarkers(buildFlyoverPath([p(0, 0)]), 'mi'), []);
	assert.deepEqual(distanceMarkers(buildFlyoverPath(northLine(0.9)), 'km'), []);
});

test('speed choices are ascending and include the default', () => {
	assert.ok(FLYOVER_SPEEDS.includes(DEFAULT_FLYOVER_SPEED_MPS));
	for (let i = 1; i < FLYOVER_SPEEDS.length; i++) assert.ok(FLYOVER_SPEEDS[i] > FLYOVER_SPEEDS[i - 1]);
});

test('advance moves at constant ground speed', () => {
	assert.equal(advance(0, 1000, 250, 10000), 250);
	assert.equal(advance(100, 16, 250, 10000), 104);
	assert.equal(advance(advance(0, 500, 250, 10000), 500, 250, 10000), 250);
});

test('advance clamps to [0, totalM]', () => {
	assert.equal(advance(9900, 1000, 250, 10000), 10000);
	assert.equal(advance(10000, 1000, 250, 10000), 10000);
	assert.equal(advance(-50, 0, 250, 10000), 0);
	assert.equal(advance(20000, 0, 250, 10000), 10000);
});

test('advance never rewinds and survives non-finite inputs', () => {
	assert.equal(advance(500, -1000, 250, 10000), 500);
	assert.equal(advance(500, 1000, -250, 10000), 500);
	assert.equal(advance(500, Number.NaN, 250, 10000), 500);
	assert.equal(advance(500, 1000, Number.POSITIVE_INFINITY, 10000), 500);
	assert.equal(advance(Number.NaN, 1000, 250, 10000), 250);
	assert.equal(advance(500, 1000, 250, Number.NaN), 0);
	assert.equal(advance(500, 1000, 250, 0), 0);
	assert.equal(advance(500, 1000, 250, -1), 0);
});
