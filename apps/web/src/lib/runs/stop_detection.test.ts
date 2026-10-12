import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	detectStops,
	STOP_HALF_WINDOW_S,
	STOP_MIN_HALF_FIXES,
	STOP_RADIUS_M,
	STOP_SPEED_MPS,
} from './gps_distance';

// detectStops decides which fixes of a Doppler-less track count as standing
// still, and the smoother credits no distance there. A false positive eats
// real distance; a false negative lets GPS wander inflate a paused run.

type Fix = readonly [number, number, number];

/** Deterministic ±amp metre wobble around a point, one fix per `dt` seconds. */
function standing(t0: number, seconds: number, x: number, y: number, amp = 2, dt = 1): Fix[] {
	const out: Fix[] = [];
	for (let t = t0; t < t0 + seconds; t += dt) {
		out.push([t, x + amp * Math.sin(t * 1.7), y + amp * Math.cos(t * 1.3)]);
	}
	return out;
}

function moving(t0: number, seconds: number, x0: number, speed: number, dt = 1): Fix[] {
	const out: Fix[] = [];
	for (let t = t0; t < t0 + seconds; t += dt) out.push([t, x0 + speed * (t - t0), 0]);
	return out;
}

test('the published thresholds are the ones the spec names', () => {
	assert.equal(STOP_HALF_WINDOW_S, 20);
	assert.equal(STOP_MIN_HALF_FIXES, 3);
	assert.equal(STOP_SPEED_MPS, 0.5);
	assert.equal(STOP_RADIUS_M, 10);
});

test('standing still with a little GPS wobble is flagged once both half-windows fill', () => {
	const fixes = standing(0, 120, 0, 0);
	const stops = detectStops(fixes);
	assert.equal(stops.length, fixes.length);
	// The first fixes have no left half-window yet, and the last none on the right.
	assert.deepEqual(stops.slice(0, STOP_MIN_HALF_FIXES), [false, false, false]);
	assert.equal(stops[stops.length - 1], false);
	assert.ok(stops.slice(10, 110).every(Boolean));
});

test('a steady jog is never flagged', () => {
	const stops = detectStops(moving(0, 300, 0, 2.5));
	assert.equal(stops.filter(Boolean).length, 0);
});

test('a 1 m/s walk is movement, not a stop', () => {
	const stops = detectStops(moving(0, 300, 0, 1.0));
	assert.equal(stops.filter(Boolean).length, 0);
});

test('a traffic-light stop mid-run is flagged in the middle and nowhere near the running', () => {
	const fixes = [...moving(0, 60, 0, 3), ...standing(60, 120, 180, 0), ...moving(180, 60, 180, 3)];
	const stops = detectStops(fixes);
	assert.ok(stops.slice(90, 150).every(Boolean), 'the heart of the stop');
	assert.equal(stops.slice(0, 35).filter(Boolean).length, 0, 'the run-in');
	assert.equal(stops.slice(205).filter(Boolean).length, 0, 'the run-out');
});

test('wandering wider than the stop radius is not a stop, even with no net progress', () => {
	// Alternating 15 m either side of a point: net speed ~0, RMS 15 m > 10 m.
	const fixes: Fix[] = [];
	for (let t = 0; t < 120; t++) fixes.push([t, t % 2 === 0 ? 15 : -15, 0]);
	assert.equal(detectStops(fixes).filter(Boolean).length, 0);
});

test('sparse 10 s fixes need the expected interval, or the half-windows never fill', () => {
	const fixes = standing(0, 600, 0, 0, 2, 10);
	assert.equal(detectStops(fixes).filter(Boolean).length, 0, 'default 1 s window: 2 fixes per half');
	assert.ok(detectStops(fixes, 10).slice(10, 50).every(Boolean), 'scaled window');
});

test('an empty track and an invalid interval are handled without throwing', () => {
	assert.deepEqual(detectStops([]), []);
	const fixes = standing(0, 60, 0, 0);
	assert.deepEqual(detectStops(fixes, Number.NaN), detectStops(fixes));
	assert.deepEqual(detectStops(fixes, null), detectStops(fixes));
	assert.deepEqual(detectStops(fixes, 0.5), detectStops(fixes), 'sub-second rates keep the 1 s window');
});
