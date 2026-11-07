import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildCumulative, buildSegment } from './track_segment';
import { lineLngLat } from './track_line';
import type { TrackPoint } from '../types';

// Mirrors apps/mobile_android/test/track_segment_test.dart case for case
// (the Dart file's `nearestTrackIdx` case pairs with nearest_track_point.test.ts).

const M_PER_LAT_DEGREE = 111320;

/** A straight north-bound track of `n` points `stepM` apart, `stepS` seconds apart. */
function track(opts: { n: number; stepM: number; stepS: number; eleStep?: number; bpm?: number }): TrackPoint[] {
	const t0 = Date.UTC(2026, 0, 1);
	return Array.from({ length: opts.n }, (_, i) => ({
		lat: (i * opts.stepM) / M_PER_LAT_DEGREE,
		lng: 0,
		ts: new Date(t0 + Math.round(i * opts.stepS * 1000)).toISOString(),
		...(opts.eleStep === undefined ? {} : { ele: i * opts.eleStep }),
		...(opts.bpm === undefined ? {} : { bpm: opts.bpm }),
	}));
}

function segmentAt(points: TrackPoint[], clickIdx: number) {
	return buildSegment(points, buildCumulative(points.map(lineLngLat)), clickIdx);
}

function near(actual: number, expected: number, tolerance: number) {
	assert.ok(Math.abs(actual - expected) <= tolerance, `${actual} is not within ${tolerance} of ${expected}`);
}

test('buildCumulative returns increasing distances starting at 0', () => {
	const cum = buildCumulative(track({ n: 5, stepM: 100, stepS: 1 }).map(lineLngLat));
	assert.equal(cum.length, 5);
	assert.equal(cum[0], 0);
	for (let i = 1; i < cum.length; i++) assert.ok(cum[i] > cum[i - 1]);
	near(cum[4], 400, 5);
});

test('buildSegment returns null for tracks under 2 points', () => {
	assert.equal(segmentAt([], 0), null);
	assert.equal(segmentAt([{ lat: 0, lng: 0 }], 0), null);
});

test('buildSegment expands to ±150 m around the click index', () => {
	const seg = segmentAt(track({ n: 21, stepM: 100, stepS: 1 }), 10)!;
	assert.ok(seg.startIdx <= 10);
	assert.ok(seg.endIdx >= 10);
	assert.ok(seg.distance_m >= 190 && seg.distance_m <= 320);
});

test('buildSegment computes pace and duration from per-point timestamps', () => {
	const seg = segmentAt(track({ n: 21, stepM: 100, stepS: 100 }), 10)!;
	assert.notEqual(seg.duration_s, null);
	near(seg.avg_pace_sec_per_km!, 1000, 5);
});

test('buildSegment returns null pace when distance is below 10 m', () => {
	const seg = segmentAt(
		[
			{ lat: 0, lng: 0, ts: '2026-01-01T00:00:00.000Z' },
			{ lat: 5 / M_PER_LAT_DEGREE, lng: 0, ts: '2026-01-01T00:00:01.000Z' },
		],
		0,
	)!;
	assert.ok(seg.distance_m < 10);
	assert.equal(seg.avg_pace_sec_per_km, null);
});

test('buildSegment aggregates avg_bpm only over plausibly-valid samples', () => {
	const seg = segmentAt(track({ n: 21, stepM: 100, stepS: 1, bpm: 150 }), 10)!;
	assert.equal(seg.avg_bpm, 150);
});

test('buildSegment accumulates elevation gain only on positive deltas', () => {
	const seg = segmentAt(track({ n: 21, stepM: 100, stepS: 1, eleStep: 1 }), 10)!;
	assert.ok(seg.ele_gain_m > 0);
	assert.equal(seg.ele_loss_m, 0);
});

test('buildSegment places the window along the line by cumulative distance', () => {
	const points = track({ n: 21, stepM: 100, stepS: 1 });
	const cum = buildCumulative(points.map(lineLngLat));
	const seg = buildSegment(points, cum, 10)!;
	assert.equal(seg.start_m, cum[seg.startIdx]);
	assert.equal(seg.end_m, cum[seg.endIdx]);
	near(seg.start_m, 900, 5);
	near(seg.end_m, 1100, 5);
	assert.equal(seg.end_m - seg.start_m, seg.distance_m);
});

test("buildSegment's edge selection starts its window at the line's start", () => {
	const seg = segmentAt(track({ n: 5, stepM: 100, stepS: 1 }), 0)!;
	assert.equal(seg.start_m, 0);
	near(seg.end_m, 100, 2);
});

test('buildSegment widens past a degenerate single-point selection at the edge', () => {
	const seg = segmentAt(track({ n: 5, stepM: 100, stepS: 1 }), 4)!;
	assert.ok(seg.startIdx < seg.endIdx);
	assert.ok(seg.distance_m > 0);
});
