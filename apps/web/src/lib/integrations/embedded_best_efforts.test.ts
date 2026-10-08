// Embedded best-effort computation for imported runs. Pre-fix no importer
// wrote the fastest_{5k,10k,...}_s values, so a fast sub-distance inside a
// long imported run never reached personal_records (the refresher reads the
// promoted runs columns since 20270325_001). Keep in lockstep with Dart's
// fastestWindowOf (apps/mobile_android/lib/run_stats.dart) +
// estimatorCumulativeMetres (apps/mobile_android/lib/embedded_bests.dart).

import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { TrackPoint } from '../types';
import {
	EMBEDDED_BEST_DISTANCES,
	WINDOW_TOLERANCE_RATIO,
	computeEmbeddedBests,
	estimatorCumulativeMetres,
	fastestWindowSeconds,
	medianFixIntervalS,
} from './garmin-fit';
import { haversineMetres } from '../runs/run_stats';
import { smoothDistance } from '../runs/gps_distance';

const M_PER_DEG = 6371000 * (Math.PI / 180);

/// Even track at the equator: `segments` steps of `stepM` metres, `stepS`
/// seconds apart.
function evenTrack(segments: number, stepM: number, stepS: number, startIso = '2026-01-01T09:00:00Z'): TrackPoint[] {
	const stepDeg = stepM / M_PER_DEG;
	const startMs = Date.parse(startIso);
	const out: TrackPoint[] = [];
	for (let i = 0; i <= segments; i++) {
		out.push({ lat: 0, lng: i * stepDeg, ts: new Date(startMs + i * stepS * 1000).toISOString() });
	}
	return out;
}

test('EMBEDDED_BEST_DISTANCES matches the migration reader + Dart keys', () => {
	assert.deepEqual(EMBEDDED_BEST_DISTANCES, [
		['fastest_5k_s', 5000],
		['fastest_10k_s', 10000],
		['fastest_half_marathon_s', 21097.5],
		['fastest_marathon_s', 42195],
	]);
});

test('computeEmbeddedBests — fewer than 3 points writes nothing', () => {
	assert.deepEqual(computeEmbeddedBests(evenTrack(1, 100, 30)), {});
});

test('computeEmbeddedBests — a sub-5km track has no bests', () => {
	assert.deepEqual(computeEmbeddedBests(evenTrack(40, 100, 30)), {}); // 4 km
});

test('computeEmbeddedBests — even 6 km run yields ~total-time 5k, no 10k', () => {
	const bests = computeEmbeddedBests(evenTrack(60, 100, 30)); // 6 km @ 5:00/km
	const fast5k = bests.fastest_5k_s ?? -1;
	assert.ok(fast5k >= 1495 && fast5k <= 1505, `got ${bests.fastest_5k_s}`);
	assert.equal(bests.fastest_10k_s, undefined);
});

test('computeEmbeddedBests — a fast 5k inside a long run is detected', () => {
	// First fifty steps fast (20 s a step), the rest slow (40 s a step). The
	// track runs 104 steps rather than 100 so the slow tail holds a 10 km
	// window. The smoother spreads the 2:1 pace change across both sides of
	// it, so the fast half credits ~8 m short and its best reads ~1016 s.
	const stepDeg = 100.01 / M_PER_DEG;
	const startMs = Date.parse('2026-01-01T09:00:00Z');
	const track: TrackPoint[] = [{ lat: 0, lng: 0, ts: new Date(startMs).toISOString() }];
	let t = startMs;
	for (let i = 1; i <= 104; i++) {
		t += (i <= 50 ? 20 : 40) * 1000;
		track.push({ lat: 0, lng: i * stepDeg, ts: new Date(t).toISOString() });
	}
	const bests = computeEmbeddedBests(track);
	// Embedded fast 5k (~1016 s) beats the whole-run-scaled pace (1500 s).
	const fast5k = bests.fastest_5k_s ?? -1;
	const fast10k = bests.fastest_10k_s ?? -1;
	assert.ok(fast5k >= 995 && fast5k <= 1020, `got ${bests.fastest_5k_s}`);
	// The 10 km window reads ~2998 s against the 3 000 s the straight line
	// gives.
	assert.ok(fast10k >= 2990 && fast10k <= 3040, `got ${bests.fastest_10k_s}`);
	assert.equal(bests.fastest_half_marathon_s, undefined);
});

test('computeEmbeddedBests — a track with no timestamps writes nothing (no fake bests)', () => {
	const stepDeg = 100 / M_PER_DEG;
	const track: TrackPoint[] = Array.from({ length: 61 }, (_, i) => ({ lat: 0, lng: i * stepDeg }));
	assert.deepEqual(computeEmbeddedBests(track), {});
});

test('fastestWindowSeconds — null when the track is shorter than the window', () => {
	assert.equal(fastestWindowSeconds(evenTrack(10, 100, 30), 5000), null);
});

test('fastestWindowSeconds — a track that measures exactly the window still yields a best', () => {
	// Fifty 100 m legs at the equator IS a 5 km run at 5:00/km, and the
	// accumulated haversine sum of it measures 4999.999 999 999 998 2 m —
	// 1.819e-12 m short. Compared strictly, that decided there was no 5 km
	// effort in a 5 km run on the last bit of a float. `WINDOW_TOLERANCE_RATIO`
	// scales with the window because the drift does; the fixture is the suite's
	// own `evenTrack`, so the case is the ordinary one rather than a contrivance.
	const track = evenTrack(50, 100, 30);
	let cum = 0;
	for (let i = 1; i < track.length; i++) {
		cum += haversineMetres(track[i - 1].lat, track[i - 1].lng, track[i].lat, track[i].lng);
	}
	assert.ok(cum < 5000, `fixture must land short of the window, measured ${cum}`);
	assert.ok(5000 - cum < 1e-9, `and only just, measured ${5000 - cum}`);
	assert.equal(fastestWindowSeconds(track, 5000), 1500);
	assert.equal(fastestWindowSeconds(track, 5000, track.map((_, i) => i * 100)), 1500);
});

test('fastestWindowSeconds — the tolerance is relative, so it never admits a real shortfall', () => {
	// A millimetre short of the window is a real shortfall at every distance
	// the app measures: `WINDOW_TOLERANCE_RATIO` of the marathon window is
	// 42 µm, so a millimetre is more than twenty times the widest slack the
	// constant ever grants and the answer stays null.
	assert.ok(WINDOW_TOLERANCE_RATIO * 42195 < 0.001);
	const short = evenTrack(50, 100 - 0.001 / 50, 30);
	assert.equal(fastestWindowSeconds(short, 5000), null);
});

test('computeEmbeddedBests — GPS zig-zag no longer closes the 5k window early', () => {
	// 6 km due east at 5:00/km, one fix a second, each fix 2 m either side of
	// the line: the hop-sum reads ~9.4 km and its 5k ~960 s.
	const startMs = Date.parse('2026-04-01T00:00:00Z');
	const track: TrackPoint[] = Array.from({ length: 1801 }, (_, i) => ({
		lat: (i % 2 === 1 ? 2 : -2) / M_PER_DEG,
		lng: (i * (6000 / 1800)) / M_PER_DEG,
		ts: new Date(startMs + i * 1000).toISOString(),
	}));
	const raw = fastestWindowSeconds(track, 5000) ?? -1;
	assert.ok(raw > 0 && raw < 1100, `fixture must be noisy, got ${raw}`);
	const s = computeEmbeddedBests(track, 'run').fastest_5k_s ?? -1;
	assert.ok(s >= 1480 && s <= 1520, `got ${s}`);
});

test('estimatorCumulativeMetres — non-decreasing, carries over untimestamped points', () => {
	const startMs = Date.parse('2026-04-01T00:00:00Z');
	const track: TrackPoint[] = Array.from({ length: 21 }, (_, i) => ({
		lat: 0,
		lng: (i * 3) / M_PER_DEG,
		...(i === 10 ? {} : { ts: new Date(startMs + i * 1000).toISOString() }),
	}));
	const cum = estimatorCumulativeMetres(track);
	assert.equal(cum.length, track.length);
	assert.equal(cum[0], 0);
	for (let i = 1; i < cum.length; i++) assert.ok(cum[i] >= cum[i - 1], `dropped at ${i}`);
	assert.equal(cum[10], cum[9]);
});

test('estimatorCumulativeMetres — measures on the smoothed distance a saved run carries', () => {
	// The fallback must read the same smoother the recorder saves and the
	// recompute writes, not the forward filter the live screen shows: the
	// cumulative's last entry is smoothDistance's per-event figure.
	const startMs = Date.parse('2026-04-01T00:00:00Z');
	const track: TrackPoint[] = Array.from({ length: 301 }, (_, i) => ({
		lat: (i % 2 === 1 ? 2 : -2) / M_PER_DEG,
		lng: (i * 3) / M_PER_DEG,
		ts: new Date(startMs + i * 1000).toISOString(),
	}));
	const cum = estimatorCumulativeMetres(track);
	const smoothed = smoothDistance(
		track.map((p, i) => ({ type: 'fix' as const, t: i, lat: p.lat, lng: p.lng })),
		10,
		1,
		null,
	);
	assert.equal(cum.length, track.length);
	cum.forEach((c, i) => assert.ok(Math.abs(c - smoothed.cumulativeM[i]) <= 1e-9, `point ${i}`));
});

test('medianFixIntervalS — the median positive interval', () => {
	const startMs = Date.parse('2026-04-01T00:00:00Z');
	const at = (s: number): TrackPoint => ({ lat: 0, lng: 0, ts: new Date(startMs + s * 1000).toISOString() });
	assert.equal(medianFixIntervalS([]), 1);
	assert.equal(medianFixIntervalS([at(0), at(1), at(1), { lat: 0, lng: 0 }, at(2), at(7), at(67)]), 3);
});
