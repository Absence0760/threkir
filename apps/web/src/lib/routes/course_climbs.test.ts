import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { FlyoverPath } from './flyover_path';
import {
	CLIMB_END_DROP_M,
	CLIMB_MIN_GRADE_PCT,
	CLIMB_START_GAIN_M,
	climbEndDropM,
	courseReliefM,
	detectClimbs,
	elevationStrip,
	PLANNED_CLIMB_MIN_GAIN_M,
	PLANNED_CLIMB_MIN_GRADE_PCT,
	PLANNED_CLIMB_WINDOW_M,
} from './course_climbs';
import { computeRealSplits, trackCumulativeMetres } from '../runs/run_stats';
import type { TrackPoint } from '../types';

const REC = { source: 'recorded' } as const;

/// A path from `[distance, elevation]` stops. Only `cumM` and `ele` are read,
/// so the coordinates are placeholders.
function path(stops: [number, number | null][]): FlyoverPath {
	return {
		points: stops.map(([, ele], i) => ({ lat: 0, lng: i * 1e-5, ele })),
		cumM: stops.map(([d]) => d),
		totalM: stops.length ? stops[stops.length - 1][0] : 0,
	};
}

/// `[distance, elevation]` every `step` metres along a piecewise-linear profile.
function profile(knots: [number, number][], step = 50): [number, number][] {
	const out: [number, number][] = [];
	const end = knots[knots.length - 1][0];
	for (let d = 0; d <= end; d += step) {
		let k = 0;
		while (k < knots.length - 2 && knots[k + 1][0] < d) k++;
		const [d0, e0] = knots[k];
		const [d1, e1] = knots[k + 1];
		out.push([d, e0 + ((e1 - e0) * (d - d0)) / (d1 - d0)]);
	}
	return out;
}

test('thresholds are the watch firmware ClimbDetector constants (decisions § 359), so one hill is one climb on the wrist and in the preview', () => {
	assert.equal(CLIMB_START_GAIN_M, 20);
	assert.equal(CLIMB_MIN_GRADE_PCT, 2);
	assert.equal(CLIMB_END_DROP_M, 10);
});

test('a steady 10 % climb is reported foot to crest with its net gain and average grade', () => {
	const p = path(profile([[0, 100], [500, 150], [1000, 100]]));
	const [c, ...rest] = detectClimbs(p, REC);
	assert.equal(rest.length, 0);
	assert.equal(c.startM, 0);
	assert.equal(c.endM, 500);
	assert.equal(c.gainM, 50);
	assert.equal(c.avgGradePct, 10);
	assert.equal(c.name, null);
});

test('a roller under the 20 m opening gain is not a climb, however steep', () => {
	assert.deepEqual(detectClimbs(path(profile([[0, 100], [150, 115], [300, 100]])), REC), []);
});

test('a false flat under 2 % average grade is not a climb, however much it gains', () => {
	// 30 m over 4 km is 0.75 %.
	assert.deepEqual(detectClimbs(path(profile([[0, 100], [4000, 130]], 200)), REC), []);
});

test('a flat approach is not part of the climb: the foot is where the road starts rising', () => {
	const p = path(profile([[0, 100], [1000, 100], [1500, 150], [2000, 150]]));
	const [c] = detectClimbs(p, REC);
	assert.equal(c.startM, 1000);
	assert.equal(c.endM, 1500);
	assert.equal(c.avgGradePct, 10);
});

test('a flat approach before a ramp too gentle from the flat start opens no climb, exactly as on the watch', () => {
	// 30 m at 4 % after 1 km dead flat: from the flat's start (the watch's
	// foot) the grade is 30/1750 = 1.7 %, under the gate.
	assert.deepEqual(detectClimbs(path(profile([[0, 100], [1000, 100], [1750, 130], [2000, 115]])), REC), []);
});

test('a short steep ramp at the end of a long false flat stays unmarked, as on the watch', () => {
	// 30 m over 4 km, then 25 m at 8 %: 55 m over 4.3 km from the foot is 1.3 %.
	const p = path(profile([[0, 100], [4000, 130], [4300, 155], [4600, 140]], 50));
	assert.deepEqual(detectClimbs(p, REC), []);
});

test('the closing drop is two noise bands for noisy altitude, never below the watch 10 m', () => {
	assert.equal(climbEndDropM(3), 10);
	assert.equal(climbEndDropM(10), 20);
	assert.equal(climbEndDropM(Number.NaN), 10);
});

test('a 12 m wobble halfway up a hill splits it on a route band but not on the phone-GPS band', () => {
	const p = path(profile([[0, 100], [500, 150], [550, 138], [1100, 200], [1500, 170]]));
	assert.equal(detectClimbs(p, REC).length, 2);
	const gps = detectClimbs(p, { source: 'recorded', noiseBandM: 10 });
	assert.equal(gps.length, 1);
	assert.deepEqual([gps[0].startM, gps[0].endM, gps[0].gainM], [0, 1100, 100]);
});

test('two ramps separated by a dip shallower than 10 m merge into one climb with the net gain', () => {
	const p = path(profile([[0, 100], [500, 150], [600, 142], [1100, 192], [1600, 140]]));
	const climbs = detectClimbs(p, REC);
	assert.equal(climbs.length, 1);
	assert.equal(climbs[0].startM, 0);
	assert.equal(climbs[0].endM, 1100);
	assert.equal(climbs[0].gainM, 92);
});

test('a descent of 10 m or more splits two climbs, and the second is measured from its own foot', () => {
	const p = path(profile([[0, 100], [500, 150], [700, 125], [1200, 175], [1500, 160]]));
	const climbs = detectClimbs(p, REC);
	assert.equal(climbs.length, 2);
	assert.deepEqual([climbs[0].startM, climbs[0].endM, climbs[0].gainM], [0, 500, 50]);
	assert.deepEqual([climbs[1].startM, climbs[1].endM, climbs[1].gainM], [700, 1200, 50]);
});

test('a course that finishes on the climb reports it ending at the high point', () => {
	const [c] = detectClimbs(path(profile([[0, 100], [600, 160]])), REC);
	assert.equal(c.endM, 600);
	assert.equal(c.gainM, 60);
});

test('a climb gain is net height, the splits table definition: over a climb that starts and ends on split boundaries the two agree', () => {
	// Flat km 1, climbing km 2-3, descending km 4, along the equator so the
	// splits read the same haversine distances the path is built on.
	const degPerM = 1 / 111_194.93;
	const ele = (d: number) => (d <= 1000 ? 100 : d <= 3000 ? 100 + (d - 1000) * 0.06 : 220 - (d - 3000) * 0.05);
	const track: TrackPoint[] = [];
	for (let d = 0; d <= 4000; d += 25) {
		track.push({ lat: 0, lng: d * degPerM, ele: ele(d), ts: new Date(Date.UTC(2026, 0, 1, 8, 0, d / 4)).toISOString() });
	}
	const cumM = trackCumulativeMetres(track);
	const p: FlyoverPath = {
		points: track.map((t) => ({ lat: t.lat, lng: t.lng, ele: t.ele ?? null })),
		cumM,
		totalM: cumM[cumM.length - 1],
	};
	const splits = computeRealSplits(track, 1000);
	const [c] = detectClimbs(p, REC);
	assert.equal(Math.round(c.startM), 1000);
	assert.equal(Math.round(c.endM), 3000);
	assert.equal(c.gainM, (splits[1].elevation_m ?? 0) + (splits[2].elevation_m ?? 0));
	assert.equal(c.gainM, 120);
});

test('points without elevation are skipped, not read as sea level', () => {
	const stops: [number, number | null][] = profile([[0, 100], [500, 150], [1000, 100]]);
	stops[3][1] = null;
	stops[12][1] = null;
	const [c] = detectClimbs(path(stops), REC);
	assert.equal(c.gainM, 50);
	assert.equal(c.startM, 0);
});

test('an all-zero series is the failed-lookup sentinel, not terrain: no climbs and no strip', () => {
	const p = path(profile([[0, 0], [1000, 0]]));
	assert.deepEqual(detectClimbs(p, REC), []);
	assert.deepEqual(elevationStrip(p, 10), []);
});

test('a path with no elevation at all has no climbs and no strip', () => {
	const p = path([[0, null], [500, null], [1000, null]]);
	assert.deepEqual(detectClimbs(p, REC), []);
	assert.deepEqual(elevationStrip(p, 10), []);
});

test('a name is attached to the climb whose span contains its distance, and only that one', () => {
	const p = path(profile([[0, 100], [500, 150], [700, 125], [1200, 175], [1500, 160]]));
	const climbs = detectClimbs(p, {
		source: 'recorded',
		names: [
			{ dM: 900, name: 'Second hill' },
			{ dM: 250, name: 'First hill' },
			{ dM: 600, name: 'In the dip' },
			{ dM: 1400, name: 'After the crest' },
		],
	});
	assert.deepEqual(climbs.map((c) => c.name), ['First hill', 'Second hill']);
});

test('a name on a span boundary still names the climb', () => {
	const p = path(profile([[0, 100], [500, 150], [1000, 100]]));
	assert.equal(detectClimbs(p, { source: 'recorded', names: [{ dM: 500, name: 'Crest' }] })[0].name, 'Crest');
	assert.equal(detectClimbs(p, { source: 'recorded', names: [{ dM: 0, name: 'Foot' }] })[0].name, 'Foot');
});

/// A deterministic ±`amp` m jitter (an LCG), the scatter a terrain model's
/// heights carry under trees and buildings.
function jitter(stops: [number, number][], amp: number, seed = 1): [number, number][] {
	let x = seed;
	return stops.map(([d, e]) => {
		x = (x * 1103515245 + 12345) % 2147483648;
		return [d, e + (x / 2147483648 - 0.5) * 2 * amp];
	});
}

/// A random-walk drift of up to `step` m a sample, the shape of phone GPS
/// altitude over a flat course.
function drift(stops: [number, number][], step: number, seed = 1): [number, number][] {
	let x = seed;
	let w = 0;
	return stops.map(([d, e]) => {
		x = (x * 1103515245 + 12345) % 2147483648;
		w = (w + (x / 2147483648 - 0.5) * 2 * step) * 0.95;
		return [d, e + w];
	});
}

const PLANNED = { source: 'planned' } as const;

/// Philadelphia Marathon from the race chart figures in #1281: low by the
/// river, a gentle rise to km 11.3, then +26 m to km 13.1, about +28 m over
/// km 14.6-16.8 whose km 15-16 is +20 m, and +27 m over km 19.9-21.9.
const PHILLY: [number, number][] = [
	[0, 8], [6000, 6], [11_300, 14], [13_100, 40], [14_000, 24], [14_600, 22], [15_000, 25],
	[16_000, 45], [16_800, 50], [17_800, 30], [19_900, 18], [21_900, 45], [23_000, 20], [42_195, 12],
];

/// A Berlin-like flat marathon: 18 m of relief over 42 km.
const FLAT_MARATHON: [number, number][] = [
	[0, 34], [6000, 40], [12_000, 36], [20_000, 48], [26_000, 44], [34_000, 52], [42_195, 38],
];

test('a planned course opens a climb at 20 m within 2 km, a 1 % average', () => {
	assert.equal(PLANNED_CLIMB_MIN_GAIN_M, 20);
	assert.equal(PLANNED_CLIMB_MIN_GRADE_PCT, 1);
	assert.equal(PLANNED_CLIMB_WINDOW_M, 2000);
});

test('Philadelphia (#1281): no climbs under the watch rule, its three hills on the planned rule', () => {
	const p = path(profile(PHILLY));
	assert.deepEqual(detectClimbs(p, REC), []);
	const climbs = detectClimbs(p, PLANNED);
	assert.deepEqual(
		climbs.map((c) => [c.startM, c.endM, c.gainM]),
		[
			[11_300, 13_100, 26],
			[15_000, 16_800, 25],
			[19_900, 21_900, 27],
		],
	);
	for (const c of climbs) assert.ok(c.avgGradePct > 1.3 && c.avgGradePct < 1.5, String(c.avgGradePct));
});

test('Philadelphia keeps its three climbs under terrain-model scatter of 1.5 m and 3 m', () => {
	for (const amp of [1.5, 3]) {
		const climbs = detectClimbs(path(jitter(profile(PHILLY), amp)), PLANNED);
		assert.equal(climbs.length, 3, `±${amp} m`);
		for (const c of climbs) assert.ok(c.gainM >= 20, `±${amp} m gain ${c.gainM}`);
	}
});

test('terrain scatter inflates a planned gain by at most twice its amplitude', () => {
	const truth = detectClimbs(path(profile(PHILLY)), PLANNED).map((c) => c.gainM);
	for (const amp of [1.5, 3]) {
		for (const seed of [1, 7, 42]) {
			const got = detectClimbs(path(jitter(profile(PHILLY), amp, seed)), PLANNED).map((c) => c.gainM);
			assert.equal(got.length, truth.length, `±${amp} m seed ${seed}`);
			got.forEach((g, i) => assert.ok(Math.abs(g - truth[i]) <= 2 * amp + 0.5, `±${amp} m seed ${seed}: ${g} vs ${truth[i]}`));
		}
	}
});

test('a net-downhill course with scatter has no planned climbs', () => {
	const downhill: [number, number][] = [[0, 60], [8000, 30], [16_000, 10], [24_000, 12], [32_000, 8], [42_195, 15]];
	assert.deepEqual(detectClimbs(path(jitter(profile(downhill), 1.5)), PLANNED), []);
});

test('two heights at one distance cannot make a planned climb with no length', () => {
	const p = path([[0, 100], [1000, 100], [1000, 125], [1500, 124], [2000, 110]]);
	for (const c of detectClimbs(p, PLANNED)) assert.ok(c.endM > c.startM, JSON.stringify(c));
});

test('a fix whose distance runs backwards is dropped, so a foot never lands behind the point before it', () => {
	const stops = profile([[0, 100], [1000, 100], [1500, 150], [2000, 150]]);
	// A stray fix at the flat's end, reading as if 200 m back and lower.
	stops.splice(21, 0, [800, 95]);
	const [c] = detectClimbs(path(stops), REC);
	assert.equal(c.startM, 1000);
	assert.equal(c.gainM, 50);
});

test('a flat marathon has no climbs on the planned rule, with or without scatter', () => {
	assert.deepEqual(detectClimbs(path(profile(FLAT_MARATHON)), PLANNED), []);
	assert.deepEqual(detectClimbs(path(jitter(profile(FLAT_MARATHON), 1.5)), PLANNED), []);
});

test('a lone 24 m hill at 1.2 % over 2 km is a planned climb', () => {
	const [c, ...rest] = detectClimbs(path(profile([[0, 14], [1000, 14], [3000, 38], [4000, 20]])), PLANNED);
	assert.equal(rest.length, 0);
	assert.deepEqual([c.startM, c.endM, c.gainM], [1000, 3000, 24]);
});

test('rollers under 20 m are not planned climbs, however many', () => {
	const knots: [number, number][] = [];
	for (let k = 0; k <= 20; k++) knots.push([k * 300, k % 2 === 0 ? 100 : 115]);
	assert.deepEqual(detectClimbs(path(profile(knots)), PLANNED), []);
});

test('a 0.8 % drag is a false flat on the planned rule too, however long', () => {
	assert.deepEqual(detectClimbs(path(profile([[0, 100], [10_000, 180], [12_000, 160]], 100)), PLANNED), []);
});

test('a hilly trail gets the same climbs on both rules', () => {
	const trail = jitter(
		profile([
			[0, 300], [3000, 600], [4000, 560], [5500, 700], [8000, 420], [8400, 450], [8800, 420], [12_000, 900],
			[16_000, 300],
		]),
		2,
	);
	const rec = detectClimbs(path(trail), REC).map((c) => [c.startM, c.endM, c.gainM]);
	assert.equal(rec.length, 4);
	assert.deepEqual(detectClimbs(path(trail), PLANNED).map((c) => [c.startM, c.endM, c.gainM]), rec);
});

test('a ramp after a long false flat is marked on the planned rule, its foot at the ramp, not the flat start', () => {
	// The watch-rule case above: 30 m over 4 km, then 25 m at 8 %.
	const p = path(profile([[0, 100], [4000, 130], [4300, 155], [4600, 140]], 50));
	const [c, ...rest] = detectClimbs(p, PLANNED);
	assert.equal(rest.length, 0);
	assert.equal(c.endM, 4300);
	assert.ok(c.startM >= 3800, String(c.startM));
	assert.ok(c.gainM >= PLANNED_CLIMB_MIN_GAIN_M);
});

test('a planned climb gains at least 20 m even when its window opened over a gentler approach', () => {
	// 15 m over 3 km at 0.5 %, then 18 m at 3 %.
	const [c] = detectClimbs(path(profile([[0, 100], [3000, 115], [3600, 133], [4000, 120]])), PLANNED);
	assert.equal(c.endM, 3600);
	assert.ok(c.gainM >= 20, String(c.gainM));
	assert.ok(c.startM > 2000 && c.startM < 3000, String(c.startM));
});

test('a planned climb closes on the same 10 m drop and takes the same names', () => {
	const p = path(profile([[0, 100], [500, 150], [700, 125], [1200, 175], [1500, 160]]));
	const climbs = detectClimbs(p, { ...PLANNED, names: [{ dM: 900, name: 'Second hill' }] });
	assert.deepEqual(
		climbs.map((c) => [c.startM, c.endM, c.gainM, c.name]),
		[
			[0, 500, 50, null],
			[700, 1200, 50, 'Second hill'],
		],
	);
});

test('phone GPS drift over a flat course: the planned rule marks more phantom climbs, which is why a recorded run keeps the watch rule', () => {
	const gps = path(drift(profile(FLAT_MARATHON, 25), 3));
	const rec = detectClimbs(gps, { source: 'recorded', noiseBandM: 10 });
	const planned = detectClimbs(gps, { ...PLANNED, noiseBandM: 10 });
	assert.ok(planned.length > rec.length, `${planned.length} vs ${rec.length}`);
});

test('an all-zero or missing series has no planned climbs either', () => {
	assert.deepEqual(detectClimbs(path(profile([[0, 0], [1000, 0]])), PLANNED), []);
	assert.deepEqual(detectClimbs(path([[0, null], [1000, null]]), PLANNED), []);
});

test('the strip samples evenly from start to finish, interpolating in distance', () => {
	const strip = elevationStrip(path([[0, 100], [1000, 200], [2000, 100]]), 5);
	assert.deepEqual(strip, [
		{ dM: 0, ele: 100 },
		{ dM: 500, ele: 150 },
		{ dM: 1000, ele: 200 },
		{ dM: 1500, ele: 150 },
		{ dM: 2000, ele: 100 },
	]);
});

test('the strip interpolates across a point with no elevation and carries the nearest reading over an unread start or finish', () => {
	const strip = elevationStrip(
		path([[0, null], [500, 100], [1000, null], [1500, 200], [2000, null]]),
		5,
	);
	assert.deepEqual(strip.map((s) => s.ele), [100, 100, 150, 200, 200]);
	assert.deepEqual(strip.map((s) => s.dM), [0, 500, 1000, 1500, 2000]);
});

test('the strip needs at least two samples', () => {
	const p = path([[0, 100], [1000, 200]]);
	assert.deepEqual(elevationStrip(p, 1), []);
	assert.deepEqual(elevationStrip(p, 0), []);
	assert.deepEqual(elevationStrip(p, Number.NaN), []);
	assert.equal(elevationStrip(p, 2.9).length, 2);
});

test('the relief is highest less lowest height, skipping points without one', () => {
	assert.equal(courseReliefM(path(profile(PHILLY))), 44);
	assert.equal(courseReliefM(path([[0, 120], [500, null], [1000, 80], [1500, 95]])), 40);
});

test('a path with no readable elevation has no relief', () => {
	assert.equal(courseReliefM(path([[0, null], [1000, null]])), null);
	assert.equal(courseReliefM(path(profile([[0, 0], [1000, 0]]))), null);
});
