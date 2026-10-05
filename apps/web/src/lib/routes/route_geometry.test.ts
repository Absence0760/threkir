// Unit tests for the route-geometry helpers. Run with `node --test`
// via tsx, matching the rest of the apps/web suite:
//   npx tsx --test src/lib/routes/route_geometry.test.ts
//
// Mirror of `apps/mobile_android/test/route_geometry_test.dart` —
// keep this file in lockstep with the Dart twin.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	interpolateAlongRoute,
	polylineLengthMetres,
	markerPointAtDistance,
	progressAlongRoute,
	type RouteProgress,
	type RouteWaypoint,
} from './route_geometry';

const wp = (lat: number, lng: number, elev?: number): RouteWaypoint => ({
	lat,
	lng,
	elevation_m: elev,
});

test('interpolateAlongRoute — null on empty waypoints', () => {
	assert.equal(interpolateAlongRoute([], 0.5), null);
});

test('interpolateAlongRoute — null on single waypoint', () => {
	assert.equal(interpolateAlongRoute([wp(0, 0)], 0.5), null);
});

test('interpolateAlongRoute — all-coincident waypoints snap to start', () => {
	const out = interpolateAlongRoute(
		[wp(1, 1), wp(1, 1), wp(1, 1)],
		0.5,
	);
	assert.ok(out);
	assert.equal(out!.lat, 1);
	assert.equal(out!.lng, 1);
});

test('interpolateAlongRoute — fraction below 0 clamps to start', () => {
	const out = interpolateAlongRoute([wp(0, 0), wp(0, 0.001)], -1.0);
	assert.ok(out);
	assert.ok(Math.abs(out!.lng - 0) < 1e-9);
});

test('interpolateAlongRoute — fraction above 1 clamps to end', () => {
	const out = interpolateAlongRoute([wp(0, 0), wp(0, 0.001)], 2.0);
	assert.ok(out);
	assert.ok(Math.abs(out!.lng - 0.001) < 1e-9);
});

test('interpolateAlongRoute — fraction = 0 returns start exactly', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.005), wp(0, 0.010)],
		0.0,
	);
	assert.equal(out!.lat, 0);
	assert.ok(Math.abs(out!.lng - 0) < 1e-9);
});

test('interpolateAlongRoute — fraction = 1 returns end exactly', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.005), wp(0, 0.010)],
		1.0,
	);
	assert.equal(out!.lat, 0);
	assert.ok(Math.abs(out!.lng - 0.010) < 1e-9);
});

test('interpolateAlongRoute — fraction = 0.5 on even-spaced lands at midpoint', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.005), wp(0, 0.010)],
		0.5,
	);
	assert.ok(Math.abs(out!.lng - 0.005) < 1e-6);
});

test('interpolateAlongRoute — distance-weighted (long segment dominates)', () => {
	// Short (1 unit) + long (9 units). Fraction 0.5 of total
	// distance (5 units) lands INSIDE the long segment — not at
	// the corner. Catches a regression to naive index-weighted.
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.001), wp(0, 0.010)],
		0.5,
	);
	assert.ok(Math.abs(out!.lng - 0.005) < 1e-6);
});

test('interpolateAlongRoute — 4-equal-leg at 0.25 lands at first corner', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.001), wp(0, 0.002), wp(0, 0.003), wp(0, 0.004)],
		0.25,
	);
	assert.ok(Math.abs(out!.lng - 0.001) < 1e-6);
});

test('interpolateAlongRoute — out-and-back uses path distance, not chord', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.001), wp(0, 0)],
		0.5,
	);
	// At the turn-around, NOT at the chord midpoint.
	assert.ok(Math.abs(out!.lng - 0.001) < 1e-6);
});

test('interpolateAlongRoute — elevation lerps linearly', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0, 100), wp(0, 0.001, 200)],
		0.5,
	);
	assert.ok(Math.abs((out!.elevation_m ?? 0) - 150) < 0.01);
});

test('interpolateAlongRoute — lerp tolerates one-sided null', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.001, 50)],
		0.5,
	);
	assert.equal(out!.elevation_m, 50);
});

test('interpolateAlongRoute — returns null elevation when both sides null', () => {
	const out = interpolateAlongRoute([wp(0, 0), wp(0, 0.001)], 0.5);
	assert.equal(out!.elevation_m, null);
});

test('interpolateAlongRoute — non-finite fraction returns null (no NaN lat/lng)', () => {
	const line = [wp(0, 0), wp(0, 0.010)];
	assert.equal(interpolateAlongRoute(line, NaN), null);
	assert.equal(interpolateAlongRoute(line, Infinity), null);
	assert.equal(interpolateAlongRoute(line, -Infinity), null);
});

test('polylineLengthMetres — empty / single → 0', () => {
	assert.equal(polylineLengthMetres([]), 0);
	assert.equal(polylineLengthMetres([wp(0, 0)]), 0);
});

test('polylineLengthMetres — 100 m segment at equator ≈ 100 m', () => {
	const metresPerDegLngAtEquator = 111320.0;
	const out = polylineLengthMetres([
		wp(0, 0),
		wp(0, 100 / metresPerDegLngAtEquator),
	]);
	assert.ok(Math.abs(out - 100) < 1);
});

test('polylineLengthMetres — multi-segment lengths sum', () => {
	const metresPerDegLngAtEquator = 111320.0;
	const step = 100 / metresPerDegLngAtEquator;
	const out = polylineLengthMetres([wp(0, 0), wp(0, step), wp(0, 2 * step)]);
	assert.ok(Math.abs(out - 200) < 1);
});

test('interpolateAlongRoute — southern-hemisphere is symmetric', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(-0.005, 0), wp(-0.010, 0)],
		0.5,
	);
	assert.ok(Math.abs(out!.lat - -0.005) < 1e-6);
	assert.equal(out!.lng, 0);
});

test('interpolateAlongRoute — negative longitude (Americas) is safe', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, -0.005), wp(0, -0.010)],
		0.5,
	);
	assert.ok(Math.abs(out!.lng - -0.005) < 1e-6);
});

test('interpolateAlongRoute — 2-waypoint polyline at fraction=0.5 → midpoint', () => {
	// Minimum valid input — pin the smallest case the scrubber must
	// support.
	const out = interpolateAlongRoute([wp(0, 0), wp(0, 0.010)], 0.5);
	assert.ok(Math.abs(out!.lng - 0.005) < 1e-6);
});

test('interpolateAlongRoute — skips zero-length segments (no poison from duplicate waypoints)', () => {
	// Defence-in-depth: the route builder\'s 5-m dedupe should
	// guarantee no exact duplicates, but if they leak through the
	// helper must skip and land in the next real segment.
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0), wp(0, 0.010)],
		0.5,
	);
	assert.ok(Math.abs(out!.lng - 0.005) < 1e-6);
});

test('interpolateAlongRoute — 200-point polyline runs under 50 ms (O(n) guard)', () => {
	const wps: RouteWaypoint[] = [];
	for (let i = 0; i <= 200; i++) wps.push(wp(0, i * 0.0001));
	const start = performance.now();
	const out = interpolateAlongRoute(wps, 0.5);
	const elapsed = performance.now() - start;
	assert.ok(out !== null);
	assert.ok(
		elapsed < 50,
		`Expected <50ms, got ${elapsed.toFixed(1)}ms — quadratic regression?`,
	);
});

const metresPerDegLng = 111320.0;
const alongOf = (point: { lat: number; lng: number }, wps: RouteWaypoint[]) =>
	progressAlongRoute(point, wps, null)?.alongM ?? null;
const distWp = (lng: number): RouteWaypoint => wp(0, lng / metresPerDegLng);

test('progressAlongRoute (no previous reading) — null on < 2 waypoints', () => {
	assert.equal(alongOf({ lat: 0, lng: 0 }, []), null);
	assert.equal(alongOf({ lat: 0, lng: 0 }, [wp(0, 0)]), null);
});

test('progressAlongRoute (no previous reading) — point on a vertex returns its cumulative distance', () => {
	// Three 100-m legs along the equator. The 2nd vertex is at 200 m.
	const wps = [distWp(0), distWp(100), distWp(200), distWp(300)];
	const d = alongOf(wps[2], wps);
	assert.ok(d !== null);
	assert.ok(Math.abs(d! - 200) < 1, `got ${d}`);
});

test('progressAlongRoute (no previous reading) — point mid-segment returns the interpolated distance', () => {
	const wps = [distWp(0), distWp(100), distWp(200)];
	const d = alongOf(distWp(150), wps);
	assert.ok(d !== null);
	assert.ok(Math.abs(d! - 150) < 1, `got ${d}`);
});

test('progressAlongRoute (no previous reading) — perpendicular offset still maps to the right along-distance', () => {
	// 50 m north of the 150-m mark — projects back down to 150 m.
	const wps = [distWp(0), distWp(100), distWp(200)];
	const offset = { lat: 50 / metresPerDegLng, lng: 150 / metresPerDegLng };
	const d = alongOf(offset, wps);
	assert.ok(d !== null);
	assert.ok(Math.abs(d! - 150) < 1, `got ${d}`);
});

test('progressAlongRoute (no previous reading) — point near the end maps near totalLength', () => {
	const wps = [distWp(0), distWp(100), distWp(200)];
	const total = polylineLengthMetres(wps);
	const d = alongOf(distWp(199), wps);
	assert.ok(d !== null);
	assert.ok(Math.abs(d! - 199) < 1, `got ${d}`);
	assert.ok(d! <= total + 1e-6);
});

test('progressAlongRoute (no previous reading) — picks the nearest of two close segments', () => {
	// An L: east 100 m then north 100 m. A point just east of the
	// corner, slightly north, is nearest the FIRST (horizontal) leg,
	// so it maps to ~100 m, not into the vertical leg.
	const corner = distWp(100);
	const up = wp(100 / metresPerDegLng, 100 / metresPerDegLng);
	const wps = [distWp(0), corner, up];
	// Just south of the 50-m mark on the first (horizontal) leg —
	// unambiguously nearest it, far from the vertical leg.
	const probe = { lat: -2 / metresPerDegLng, lng: 50 / metresPerDegLng };
	const d = alongOf(probe, wps);
	assert.ok(d !== null);
	assert.ok(d! < 100, `expected on the first leg (<100 m), got ${d}`);
	assert.ok(Math.abs(d! - 50) < 2, `got ${d}`);
});

test('progressAlongRoute (no previous reading) — a later segment can still win', () => {
	// Guard against a fix that degenerates into "always the first segment":
	// an L (east 100 m, then north 100 m) probed 2 m east of the vertical
	// leg, near its top, must resolve into the SECOND leg (>100 m).
	const wps = [
		distWp(0),
		distWp(100),
		wp(100 / metresPerDegLng, 100 / metresPerDegLng),
	];
	const probe = { lat: 90 / metresPerDegLng, lng: 102 / metresPerDegLng };
	const d = alongOf(probe, wps);
	assert.ok(d !== null);
	assert.ok(Math.abs(d! - 190) < 2, `expected ~190 m on the second leg, got ${d}`);
});

test('progressAlongRoute (no previous reading) — an out-and-back does not flip limbs on 1 cm of jitter', () => {
	// 3.47 km due north and back (0.03125° = 1/32, so both limbs are the
	// same ground twice over). Ranking candidates by a perpendicular measured
	// inside each segment's OWN planar frame compares incommensurable numbers:
	// the return limb anchors its frame 3.5 km further north, where cos(lat)
	// is smaller, so it always reports the smaller "distance" to a point that
	// is exactly as far from both. A GPS fix 1 cm off the line then resolves
	// 3.5 km further along the course than the same fix on it.
	const oab = [wp(45, 0), wp(45.03125, 0), wp(45, 0)];
	const total = polylineLengthMetres(oab);
	const mid = 45.015625; // half way up the outbound limb
	const oneCm = 0.01 / (metresPerDegLng * Math.cos((mid * Math.PI) / 180));

	const onLine = alongOf({ lat: mid, lng: 0 }, oab);
	const east = alongOf({ lat: mid, lng: oneCm }, oab);
	const west = alongOf({ lat: mid, lng: -oneCm }, oab);
	assert.ok(onLine !== null && east !== null && west !== null);

	assert.ok(
		Math.abs(east! - onLine!) < 1,
		`1 cm east moved the answer ${Math.abs(east! - onLine!).toFixed(0)} m`,
	);
	assert.ok(
		Math.abs(west! - onLine!) < 1,
		`1 cm west moved the answer ${Math.abs(west! - onLine!).toFixed(0)} m`,
	);
	assert.ok(
		Math.abs(onLine! - total / 4) < 1,
		`expected the outbound limb (~${(total / 4).toFixed(0)} m), got ${onLine}`,
	);
});

test('progressAlongRoute (no previous reading) — clamps to [0, totalLength]', () => {
	const wps = [distWp(0), distWp(100), distWp(200)];
	const total = polylineLengthMetres(wps);
	// Way past the end, off to the side.
	const far = distWp(10_000);
	const d = alongOf(far, wps);
	assert.ok(d !== null);
	assert.ok(d! >= 0 && d! <= total + 1e-6, `got ${d} (total ${total})`);
});

test('progressAlongRoute (no previous reading) — null on a non-finite point (not 0)', () => {
	const wps = [distWp(0), distWp(100), distWp(200)];
	// A finite point still resolves to its along-distance.
	assert.ok(alongOf(distWp(100), wps) !== null);
	// A NaN or Infinity fix is "unknown position", not "at the start".
	assert.equal(alongOf({ lat: NaN, lng: 0 }, wps), null);
	assert.equal(alongOf({ lat: 0, lng: Infinity }, wps), null);
});

// ── markerPointAtDistance — the "place a marker at mile 5" input path ──

test('markerPointAtDistance — null on < 2 waypoints', () => {
	assert.equal(markerPointAtDistance([], 100), null);
	assert.equal(markerPointAtDistance([distWp(0)], 100), null);
});

test('markerPointAtDistance — null on a zero-length (all-coincident) line', () => {
	assert.equal(markerPointAtDistance([wp(1, 1), wp(1, 1)], 100), null);
});

test('markerPointAtDistance — null on a non-finite distance', () => {
	const wps = [distWp(0), distWp(200)];
	assert.equal(markerPointAtDistance(wps, NaN), null);
	assert.equal(markerPointAtDistance(wps, Infinity), null);
});

test('markerPointAtDistance — distance 0 returns the start', () => {
	const wps = [distWp(0), distWp(100), distWp(200)];
	const out = markerPointAtDistance(wps, 0);
	assert.ok(out);
	assert.ok(Math.abs(out!.lng - 0) < 1e-9);
});

test('markerPointAtDistance — a mid-route distance lands at that along-distance', () => {
	// Three 100-m legs on the equator → 300 m total. 150 m is the
	// midpoint of the second leg.
	const wps = [distWp(0), distWp(100), distWp(200), distWp(300)];
	const out = markerPointAtDistance(wps, 150);
	assert.ok(out);
	// Round-trip through the inverse: the point should sit ~150 m along.
	const back = alongOf(out!, wps);
	assert.ok(back !== null);
	assert.ok(Math.abs(back! - 150) < 1, `got ${back}`);
});

test('markerPointAtDistance — a distance past the end clamps to the finish', () => {
	const wps = [distWp(0), distWp(100), distWp(200)];
	const total = polylineLengthMetres(wps);
	const out = markerPointAtDistance(wps, total + 10_000);
	assert.ok(out);
	// Same point as the true end waypoint.
	assert.ok(Math.abs(out!.lng - wps[wps.length - 1].lng) < 1e-9);
	// And its along-distance is the full length, not beyond it.
	const back = alongOf(out!, wps);
	assert.ok(back !== null);
	assert.ok(Math.abs(back! - total) < 1, `got ${back} (total ${total})`);
});

test('markerPointAtDistance — a negative distance clamps to the start', () => {
	const wps = [distWp(0), distWp(100), distWp(200)];
	const out = markerPointAtDistance(wps, -500);
	assert.ok(out);
	assert.ok(Math.abs(out!.lng - 0) < 1e-9);
});

test('interpolateAlongRoute — a leg across the antimeridian stays on the leg', () => {
	const wps = [wp(0, 179.99), wp(0, -179.97)];
	const out = interpolateAlongRoute(wps, 0.5);
	assert.ok(out);
	// The midpoint of a 0.04° leg anchored at 179.99 is 180.01, which wraps
	// to -179.99 — not 0.01, half a world away.
	assert.ok(Math.abs(out!.lng - -179.99) < 1e-9, `got ${out!.lng}`);
	assert.equal(out!.lat, 0);
});

test('progressAlongRoute (no previous reading) — a point past the antimeridian projects onto the leg', () => {
	const wps = [wp(0, 179.98), wp(0, -179.96)];
	const total = polylineLengthMetres(wps);
	const along = alongOf({ lat: 0, lng: -179.99 }, wps);
	assert.ok(along !== null);
	assert.ok(Math.abs(along! - total / 2) < 1, `got ${along} of ${total}`);
});

test('polylineLengthMetres — a course across the antimeridian spans 0.06°, not 359.94°', () => {
	const wps = [wp(0, 179.98), wp(0, -179.96)];
	assert.ok(Math.abs(polylineLengthMetres(wps) - 6671.7) < 1);
});

// progressAlongRoute — the windowed matcher a live consumer follows a route
// with. Fixtures are built in metres east/north of (0,0) at the equator using
// the haversine radius, so the lengths below are exact to well under a metre.
const M_PER_DEG = (6_371_000 * Math.PI) / 180;
const en = (eastM: number, northM: number): RouteWaypoint =>
	wp(northM / M_PER_DEG, eastM / M_PER_DEG);
const at = (eastM: number, northM: number) => {
	const p = en(eastM, northM);
	return { lat: p.lat, lng: p.lng };
};
// 500 m square, start == finish, run anticlockwise: east, north, west, south.
const squareLoop = [en(0, 0), en(500, 0), en(500, 500), en(0, 500), en(0, 0)];
// 1 km out east and back to the start on the same line.
const outAndBack = [en(0, 0), en(1000, 0), en(0, 0)];

test('progressAlongRoute — null on < 2 waypoints or a non-finite point', () => {
	assert.equal(progressAlongRoute({ lat: 0, lng: 0 }, [wp(0, 0)], null), null);
	assert.equal(progressAlongRoute({ lat: Number.NaN, lng: 0 }, squareLoop, null), null);
});

test('progressAlongRoute — a loop runner at the start has the whole loop to go', () => {
	// 3 m north and 1 m east of the start: nearer the CLOSING leg (1 m) than the
	// opening one (3 m), which a global nearest-point search snaps to — reading
	// the lap as finished the instant the run starts.
	const p = progressAlongRoute(at(1, 3), squareLoop, null)!;
	assert.ok(p.alongM < 5, `alongM ${p.alongM}`);
	assert.ok(Math.abs(p.remainingM - 2000) < 5, `remainingM ${p.remainingM}`);
	assert.ok(p.offRouteM < 1.5, `offRouteM ${p.offRouteM}`);
});

test('progressAlongRoute — walking a loop keeps progress forward and on-route to the finish', () => {
	let prev: number | null = null;
	const legs: Array<[number, number, number, number]> = [
		[0, 0, 500, 0],
		[500, 0, 500, 500],
		[500, 500, 0, 500],
		[0, 500, 0, 0],
	];
	for (const [x0, y0, x1, y1] of legs) {
		for (let s = 0; s <= 50; s++) {
			const p: RouteProgress = progressAlongRoute(
				at(x0 + ((x1 - x0) * s) / 50, y0 + ((y1 - y0) * s) / 50),
				squareLoop,
				prev,
			)!;
			assert.ok(p.offRouteM < 0.5, `offRouteM ${p.offRouteM}`);
			if (prev !== null) assert.ok(p.alongM >= prev - 0.5, `${p.alongM} < ${prev}`);
			prev = p.alongM;
		}
	}
	assert.ok(Math.abs(prev! - 2000) < 1, `finished at ${prev}`);
});

test('progressAlongRoute — an out-and-back runner past the turnaround is on the return leg', () => {
	let prev: number | null = null;
	for (let m = 0; m <= 1000; m += 10) prev = progressAlongRoute(at(m, 0), outAndBack, prev)!.alongM;
	let last = progressAlongRoute(at(1000, 0), outAndBack, prev)!;
	for (let m = 990; m >= 900; m -= 10) {
		last = progressAlongRoute(at(m, 0), outAndBack, last.alongM)!;
	}
	assert.ok(Math.abs(last.alongM - 1100) < 1, `alongM ${last.alongM}`);
	assert.ok(Math.abs(last.remainingM - 900) < 1, `remainingM ${last.remainingM}`);
	assert.ok(last.offRouteM < 0.5);
});

test('progressAlongRoute — a runner genuinely off course is still measured off it', () => {
	const p = progressAlongRoute(at(250, 120), squareLoop, 250)!;
	assert.ok(Math.abs(p.offRouteM - 120) < 1, `offRouteM ${p.offRouteM}`);
	assert.ok(Math.abs(p.alongM - 250) < 1, `alongM ${p.alongM}`);
});

test('progressAlongRoute — a figure-eight crossing is read on the pass the runner is on', () => {
	// Bow-tie: the two diagonals cross at (100, 100), ~141 m in on the first
	// pass and ~624 m in on the second.
	const eight = [en(0, 0), en(200, 200), en(200, 0), en(0, 200), en(0, 0)];
	const d = Math.hypot(200, 200);
	let prev: number | null = null;
	const crossings: number[] = [];
	const legs: Array<[number, number, number, number]> = [
		[0, 0, 200, 200],
		[200, 200, 200, 0],
		[200, 0, 0, 200],
		[0, 200, 0, 0],
	];
	for (const [x0, y0, x1, y1] of legs) {
		for (let s = 0; s <= 20; s++) {
			const x = x0 + ((x1 - x0) * s) / 20;
			const y = y0 + ((y1 - y0) * s) / 20;
			const p: RouteProgress = progressAlongRoute(at(x, y), eight, prev)!;
			if (x === 100 && y === 100) crossings.push(p.alongM);
			prev = p.alongM;
		}
	}
	assert.equal(crossings.length, 2);
	assert.ok(Math.abs(crossings[0] - d / 2) < 1, `first pass ${crossings[0]}`);
	assert.ok(Math.abs(crossings[1] - (d + 200 + d / 2)) < 1, `second pass ${crossings[1]}`);
});

test('progressAlongRoute — a runner back on the line beyond the look-ahead is re-acquired', () => {
	const line = [en(0, 0), en(2000, 0)];
	const p = progressAlongRoute(at(900, 0), line, 100)!;
	assert.ok(Math.abs(p.alongM - 900) < 1, `alongM ${p.alongM}`);
});

test('progressAlongRoute — distance travelled since the last match picks the leg after a gap', () => {
	const p = progressAlongRoute(at(900, 0), outAndBack, 0, 1100)!;
	assert.ok(Math.abs(p.alongM - 1100) < 1, `alongM ${p.alongM}`);
});

test('progressAlongRoute — a non-finite previous reading is treated as no reading', () => {
	const p = progressAlongRoute(at(1, 3), squareLoop, Number.NaN, Number.NaN)!;
	assert.ok(p.alongM < 5, `alongM ${p.alongM}`);
});

test('progressAlongRoute — with no previous reading, a fix off the line takes its nearest point', () => {
	// Starting a recording 100 m beside the middle of the route: there is no
	// earlier match to hold on to, so the window at the start does not win.
	const line = [en(0, 0), en(2000, 0)];
	const p = progressAlongRoute(at(900, 100), line, null)!;
	assert.ok(Math.abs(p.alongM - 900) < 1, `alongM ${p.alongM}`);
	assert.ok(Math.abs(p.offRouteM - 100) < 1, `offRouteM ${p.offRouteM}`);
});
