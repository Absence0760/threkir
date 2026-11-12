// The VDOT numbers a runner reads against the table they were taught from.
//
// `vdotFromRace` (plan paces) and `vdotFromRun` (fitness card) are two copies
// of the Daniels formula, and `thresholdPaceSecPerKmFromVdot` inverts its
// demand curve. Their own suites pin a couple of spot values each; these pin
// the published table across the range, the two copies against each other,
// and the inverse against the forward equation, so a drifted constant in any
// one of them cannot hide behind a loose tolerance.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { vdotFromRace } from './training';
import { runTss, thresholdPaceSecPerKmFromVdot, vdotFromRun } from './fitness';

const hms = (h: number, m: number, s: number) => h * 3600 + m * 60 + s;

/// Daniels' Running Formula (3rd ed.) race-equivalence table: VDOT -> 5K,
/// 10K and marathon times.
const DANIELS: Array<[number, number, number, number]> = [
	[30, hms(0, 30, 40), hms(1, 3, 46), hms(4, 49, 17)],
	[40, hms(0, 24, 8), hms(0, 50, 3), hms(3, 49, 45)],
	[50, hms(0, 19, 57), hms(0, 41, 21), hms(3, 10, 49)],
	[60, hms(0, 17, 3), hms(0, 35, 22), hms(2, 43, 25)],
	[70, hms(0, 14, 55), hms(0, 30, 58), hms(2, 23, 12)]
];

test('vdotFromRace reproduces the published Daniels table at 5K, 10K and the marathon', () => {
	for (const [vdot, t5k, t10k, tM] of DANIELS) {
		for (const [d, t] of [
			[5000, t5k],
			[10_000, t10k],
			[42_195, tM]
		] as const) {
			const got = vdotFromRace(d, t);
			assert.ok(Math.abs(got - vdot) < 0.3, `${d} m in ${t} s: VDOT ${got.toFixed(2)}, table ${vdot}`);
		}
	}
});

test('vdotFromRun and vdotFromRace agree wherever the fitness guards admit the run', () => {
	for (const d of [1000, 1609.344, 3000, 5000, 10_000, 21_097.5, 42_195]) {
		for (const paceSecPerKm of [180, 210, 240, 300, 360, 420, 540]) {
			const t = (d / 1000) * paceSecPerKm;
			const run = vdotFromRun(d, t);
			if (run === null) continue;
			assert.ok(Math.abs(run - vdotFromRace(d, t)) < 1e-9, `${d} m at ${paceSecPerKm} s/km`);
		}
	}
});

test('vdotFromRun refuses exactly the efforts past the 90 VDOT human ceiling', () => {
	// A 5K that is just under / just over VDOT 90, found by bisection on the
	// shared formula so the test does not restate the threshold's time.
	let lo = 600;
	let hi = 1200;
	for (let i = 0; i < 60; i++) {
		const mid = (lo + hi) / 2;
		if (vdotFromRace(5000, mid) > 90) lo = mid;
		else hi = mid;
	}
	assert.equal(vdotFromRun(5000, lo - 0.5), null, 'faster than the ceiling');
	const atCeiling = vdotFromRun(5000, hi + 0.5);
	assert.ok(atCeiling !== null && atCeiling <= 90 && atCeiling > 89.9);
});

test('threshold pace is the exact inverse of the demand curve at 88 % of VDOT', () => {
	for (const vdot of [30, 40, 50, 60, 70, 80]) {
		const secPerKm = thresholdPaceSecPerKmFromVdot(vdot)!;
		const v = 60_000 / secPerKm; // m/min
		const demand = -4.6 + 0.182258 * v + 0.000104 * v * v;
		assert.ok(Math.abs(demand - 0.88 * vdot) < 1e-9, `VDOT ${vdot}`);
	}
	// Faster with every point of VDOT, never flat.
	for (let vdot = 30; vdot < 85; vdot++) {
		assert.ok(thresholdPaceSecPerKmFromVdot(vdot + 1)! < thresholdPaceSecPerKmFromVdot(vdot)!);
	}
});

test('runTss is 100 per hour at threshold, linear in time at a fixed pace, and quadratic in intensity', () => {
	const T = 250;
	// One hour at exactly threshold pace.
	assert.ok(Math.abs(runTss((3600 / T) * 1000, 3600, T) - 100) < 1e-9);
	// Twice as long at the same pace: twice the stress.
	const hour = runTss(12_000, 3600, T);
	const twoHours = runTss(24_000, 7200, T);
	assert.ok(Math.abs(twoHours - 2 * hour) < 1e-9);
	// 10 % faster than threshold for an hour: 1.1^2 x 100.
	const fast = runTss((3600 / (T / 1.1)) * 1000, 3600, T);
	assert.ok(Math.abs(fast - 121) < 1e-9);
});
