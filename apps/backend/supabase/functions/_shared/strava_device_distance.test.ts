/// Embedded bests prefer Strava's own `distance` stream over re-estimating
/// from positions, and fall back to the estimator when the stream cannot
/// stand in for it (issue #1090 item 7a). Lockstep with the web twin in
/// apps/web/src/lib/integrations/device_distance_stream.test.ts.
///
/// Run with:
///   cd apps/backend && deno test --no-check supabase/functions/_shared/strava_device_distance.test.ts

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
	buildTrackAndDistanceFromStreams,
	buildTrackFromStreams,
	computeEmbeddedBests,
	deviceCumulativeMetres,
	estimatorCumulativeMetres,
} from './strava.ts';
import { smoothDistance } from './gps_distance.ts';

const START = '2026-01-01T09:00:00Z';
const M_PER_DEG = 6371000 * (Math.PI / 180);
const streams = (o: Record<string, unknown[]>) =>
	Object.fromEntries(Object.entries(o).map(([k, v]) => [k, { data: v }]));

/// 6 km due east at 5:00/km: 100 m per 30 s.
function evenStreams(distanceOf: (i: number) => unknown) {
	const n = 61;
	return streams({
		latlng: Array.from({ length: n }, (_, i) => [0, (i * 100) / M_PER_DEG]),
		time: Array.from({ length: n }, (_, i) => i * 30),
		distance: Array.from({ length: n }, (_, i) => distanceOf(i)),
	});
}

Deno.test('deviceCumulativeMetres — a monotonic stream is rebased to the first point', () => {
	assertEquals(deviceCumulativeMetres([12, 12, 40.5, 100], 4), [0, 0, 28.5, 88]);
});

Deno.test('deviceCumulativeMetres — refuses every stream that cannot stand in for the estimator', () => {
	assertEquals(deviceCumulativeMetres(null, 3), null);
	assertEquals(deviceCumulativeMetres(undefined, 3), null);
	assertEquals(deviceCumulativeMetres([0, 10], 3), null);
	assertEquals(deviceCumulativeMetres([0], 1), null);
	assertEquals(deviceCumulativeMetres([0, NaN, 20], 3), null);
	assertEquals(deviceCumulativeMetres([0, Infinity, 20], 3), null);
	assertEquals(deviceCumulativeMetres([0, '10', 20], 3), null);
	assertEquals(deviceCumulativeMetres([0, null, 20], 3), null);
	assertEquals(deviceCumulativeMetres([-1, 0, 20], 3), null);
	assertEquals(deviceCumulativeMetres([0, 30, 20], 3), null);
	assertEquals(deviceCumulativeMetres([0, 0, 0], 3), null);
	assertEquals(deviceCumulativeMetres([55, 55, 55], 3), null);
});

Deno.test('buildTrackAndDistanceFromStreams — keeps distance aligned with the sanitised track', () => {
	const { track, distance } = buildTrackAndDistanceFromStreams(
		streams({
			latlng: [[45, -120], [91, 0], [45.001, -120], [45.002, -120]],
			distance: [0, 50, 111, 'x'],
		}),
		START,
	);
	assertEquals(track.length, 3);
	assertEquals(distance?.slice(0, 2), [0, 111]);
	assertEquals(Number.isNaN(distance?.[2]), true);
});

Deno.test('buildTrackAndDistanceFromStreams — no stream, or a misaligned one, is null', () => {
	const latlng = [[45, -120], [45.001, -120]];
	assertEquals(buildTrackAndDistanceFromStreams(streams({ latlng }), START).distance, null);
	assertEquals(
		buildTrackAndDistanceFromStreams(streams({ latlng, distance: [0] }), START).distance,
		null,
	);
});

Deno.test('buildTrackFromStreams — the stored track never carries the distance stream', () => {
	const track = buildTrackFromStreams(evenStreams((i) => i * 100), START);
	assertEquals(track.length, 61);
	assertEquals(Object.keys(track[1]).sort(), ['lat', 'lng', 'ts']);
});

Deno.test('computeEmbeddedBests — measures on a valid distance stream, not the positions', () => {
	// The stream reads 200 m per 30 s (12 km) over a 6 km track: an exact
	// 750 s 5k and 1500 s 10k, where the estimator alone finds no 10k.
	const { track, distance } = buildTrackAndDistanceFromStreams(evenStreams((i) => i * 200), START);
	const bests = computeEmbeddedBests(track, 'run', distance);
	assertEquals(bests.fastest_5k_s, 750);
	assertEquals(bests.fastest_10k_s, 1500);
});

Deno.test('computeEmbeddedBests — an invalid distance stream falls back to the estimator', () => {
	const { track } = buildTrackAndDistanceFromStreams(evenStreams((i) => i * 100), START);
	const estimated = computeEmbeddedBests(track, 'run');
	assertEquals(estimated.fastest_10k_s, undefined);
	for (const bad of [
		(i: number) => (i === 30 ? NaN : i * 200),
		(i: number) => (i === 30 ? 0 : i * 200),
		() => 0,
	]) {
		const { distance } = buildTrackAndDistanceFromStreams(evenStreams(bad), START);
		assertEquals(computeEmbeddedBests(track, 'run', distance), estimated);
	}
	assertEquals(computeEmbeddedBests(track, 'run', [0, 200]), estimated);
});

Deno.test('estimatorCumulativeMetres — the fallback reads the smoothed distance a saved run carries', () => {
	// Not the forward filter the live screen shows: the same smoother the
	// recorder saves with and the recompute writes. A zig-zag over 300 s.
	const startMs = Date.parse(START);
	const track = Array.from({ length: 301 }, (_, i) => ({
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
	assertEquals(cum.length, track.length);
	cum.forEach((c, i) => assertEquals(Math.abs(c - smoothed.cumulativeM[i]) <= 1e-9, true, `point ${i}`));
});
