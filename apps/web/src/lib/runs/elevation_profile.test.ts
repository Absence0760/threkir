import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { cumulativeMetres, elevationDomain, smoothElevation } from './elevation_profile';

/// Mirror of `apps/mobile_android/test/elevation_profile_test.dart`. Its
/// `elevationSeries` cases mirror `key_stats.test.ts` instead.

const evenSpacing = (n: number, stepM: number) => Array.from({ length: n }, (_, i) => i * stepM);

test('smoothElevation keeps a constant series constant', () => {
	const out = smoothElevation(new Array(50).fill(120), evenSpacing(50, 3));
	for (const v of out) assert.ok(Math.abs(v - 120) < 1e-9);
});

test('smoothElevation flattens per-fix altitude jitter', () => {
	const series = Array.from({ length: 200 }, (_, i) => (i % 2 === 0 ? 102 : 98));
	const out = smoothElevation(series, evenSpacing(200, 3));
	for (const v of out.slice(20, 180)) assert.ok(Math.abs(v - 100) < 0.2, `${v}`);
});

test('smoothElevation with a window wider than the track averages the whole track', () => {
	assert.deepEqual(smoothElevation([10, 20, 30], [0, 5, 10], 1000), [20, 20, 20]);
});

test('smoothElevation keeps one value per point', () => {
	assert.equal(smoothElevation([1, 2, 3, 4], evenSpacing(4, 50)).length, 4);
});

test('elevationDomain draws a flat run at least 30 m tall, centred', () => {
	const d = elevationDomain(100, 104);
	assert.ok(Math.abs(d.hi - d.lo - 36) < 1e-9);
	assert.ok(Math.abs((d.hi + d.lo) / 2 - 102) < 1e-9);
});

test('elevationDomain gives a hilly run 10 % headroom each side', () => {
	const d = elevationDomain(200, 700);
	assert.ok(Math.abs(d.lo - 150) < 1e-9);
	assert.ok(Math.abs(d.hi - 750) < 1e-9);
});

test('cumulativeMetres starts at zero and only grows', () => {
	const track = Array.from({ length: 5 }, (_, i) => ({ lat: 37 + i * 0.001, lng: -122 }));
	const cum = cumulativeMetres(track);
	assert.equal(cum[0], 0);
	for (let i = 1; i < cum.length; i++) assert.ok(cum[i] > cum[i - 1]);
});
