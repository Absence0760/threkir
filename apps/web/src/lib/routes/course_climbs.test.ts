import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { FlyoverPath } from './flyover_path';
import {
	CLIMB_END_DROP_M,
	CLIMB_MIN_GRADE_PCT,
	CLIMB_START_GAIN_M,
	climbEndDropM,
	detectClimbs,
	elevationStrip,
} from './course_climbs';
import { computeRealSplits, trackCumulativeMetres } from '../runs/run_stats';
import type { TrackPoint } from '../types';

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
	const [c, ...rest] = detectClimbs(p);
	assert.equal(rest.length, 0);
	assert.equal(c.startM, 0);
	assert.equal(c.endM, 500);
	assert.equal(c.gainM, 50);
	assert.equal(c.avgGradePct, 10);
	assert.equal(c.name, null);
});

test('a roller under the 20 m opening gain is not a climb, however steep', () => {
	assert.deepEqual(detectClimbs(path(profile([[0, 100], [150, 115], [300, 100]]))), []);
});

test('a false flat under 2 % average grade is not a climb, however much it gains', () => {
	// 30 m over 4 km is 0.75 %.
	assert.deepEqual(detectClimbs(path(profile([[0, 100], [4000, 130]], 200))), []);
});

test('a flat approach is not part of the climb: the foot is where the road starts rising', () => {
	const p = path(profile([[0, 100], [1000, 100], [1500, 150], [2000, 150]]));
	const [c] = detectClimbs(p);
	assert.equal(c.startM, 1000);
	assert.equal(c.endM, 1500);
	assert.equal(c.avgGradePct, 10);
});

test('a flat approach before a ramp too gentle from the flat start opens no climb, exactly as on the watch', () => {
	// 30 m at 4 % after 1 km dead flat: from the flat's start (the watch's
	// foot) the grade is 30/1750 = 1.7 %, under the gate.
	assert.deepEqual(detectClimbs(path(profile([[0, 100], [1000, 100], [1750, 130], [2000, 115]]))), []);
});

test('a short steep ramp at the end of a long false flat stays unmarked, as on the watch', () => {
	// 30 m over 4 km, then 25 m at 8 %: 55 m over 4.3 km from the foot is 1.3 %.
	const p = path(profile([[0, 100], [4000, 130], [4300, 155], [4600, 140]], 50));
	assert.deepEqual(detectClimbs(p), []);
});

test('the closing drop is two noise bands for noisy altitude, never below the watch 10 m', () => {
	assert.equal(climbEndDropM(3), 10);
	assert.equal(climbEndDropM(10), 20);
	assert.equal(climbEndDropM(Number.NaN), 10);
});

test('a 12 m wobble halfway up a hill splits it on a route band but not on the phone-GPS band', () => {
	const p = path(profile([[0, 100], [500, 150], [550, 138], [1100, 200], [1500, 170]]));
	assert.equal(detectClimbs(p).length, 2);
	const gps = detectClimbs(p, { noiseBandM: 10 });
	assert.equal(gps.length, 1);
	assert.deepEqual([gps[0].startM, gps[0].endM, gps[0].gainM], [0, 1100, 100]);
});

test('two ramps separated by a dip shallower than 10 m merge into one climb with the net gain', () => {
	const p = path(profile([[0, 100], [500, 150], [600, 142], [1100, 192], [1600, 140]]));
	const climbs = detectClimbs(p);
	assert.equal(climbs.length, 1);
	assert.equal(climbs[0].startM, 0);
	assert.equal(climbs[0].endM, 1100);
	assert.equal(climbs[0].gainM, 92);
});

test('a descent of 10 m or more splits two climbs, and the second is measured from its own foot', () => {
	const p = path(profile([[0, 100], [500, 150], [700, 125], [1200, 175], [1500, 160]]));
	const climbs = detectClimbs(p);
	assert.equal(climbs.length, 2);
	assert.deepEqual([climbs[0].startM, climbs[0].endM, climbs[0].gainM], [0, 500, 50]);
	assert.deepEqual([climbs[1].startM, climbs[1].endM, climbs[1].gainM], [700, 1200, 50]);
});

test('a course that finishes on the climb reports it ending at the high point', () => {
	const [c] = detectClimbs(path(profile([[0, 100], [600, 160]])));
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
	const [c] = detectClimbs(p);
	assert.equal(Math.round(c.startM), 1000);
	assert.equal(Math.round(c.endM), 3000);
	assert.equal(c.gainM, (splits[1].elevation_m ?? 0) + (splits[2].elevation_m ?? 0));
	assert.equal(c.gainM, 120);
});

test('points without elevation are skipped, not read as sea level', () => {
	const stops: [number, number | null][] = profile([[0, 100], [500, 150], [1000, 100]]);
	stops[3][1] = null;
	stops[12][1] = null;
	const [c] = detectClimbs(path(stops));
	assert.equal(c.gainM, 50);
	assert.equal(c.startM, 0);
});

test('an all-zero series is the failed-lookup sentinel, not terrain: no climbs and no strip', () => {
	const p = path(profile([[0, 0], [1000, 0]]));
	assert.deepEqual(detectClimbs(p), []);
	assert.deepEqual(elevationStrip(p, 10), []);
});

test('a path with no elevation at all has no climbs and no strip', () => {
	const p = path([[0, null], [500, null], [1000, null]]);
	assert.deepEqual(detectClimbs(p), []);
	assert.deepEqual(elevationStrip(p, 10), []);
});

test('a name is attached to the climb whose span contains its distance, and only that one', () => {
	const p = path(profile([[0, 100], [500, 150], [700, 125], [1200, 175], [1500, 160]]));
	const climbs = detectClimbs(p, {
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
	assert.equal(detectClimbs(p, { names: [{ dM: 500, name: 'Crest' }] })[0].name, 'Crest');
	assert.equal(detectClimbs(p, { names: [{ dM: 0, name: 'Foot' }] })[0].name, 'Foot');
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
