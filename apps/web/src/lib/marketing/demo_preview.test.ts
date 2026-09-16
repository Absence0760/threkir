import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	DEMO_DISTANCE_KM,
	DEMO_DISTANCE_LABEL,
	DEMO_ELEVATION,
	DEMO_HEART_RATE,
	DEMO_HR_ZONES,
	DEMO_PACE_LABEL,
	DEMO_PACE_SECONDS_PER_KM,
	DEMO_SPLITS,
	DEMO_TIME_LABEL,
	DEMO_TOTAL_SECONDS,
	DEMO_TRACK,
} from './demo_preview';

// The landing page renders this data through the product's own components,
// so a malformed point or an out-of-range percentage is a visible marketing
// defect rather than a caught exception. These pin the shapes the preview
// markup assumes.

test('the demo track is a closed loop of plausible coordinates', () => {
	assert.ok(DEMO_TRACK.length >= 32, 'too few points to read as a route');
	for (const p of DEMO_TRACK) {
		assert.ok(Number.isFinite(p.lat) && p.lat >= -90 && p.lat <= 90, `bad lat ${p.lat}`);
		assert.ok(Number.isFinite(p.lng) && p.lng >= -180 && p.lng <= 180, `bad lng ${p.lng}`);
	}
	const first = DEMO_TRACK[0];
	const last = DEMO_TRACK[DEMO_TRACK.length - 1];
	assert.equal(first.lat, last.lat, 'the loop must close so the preview reads as a lap');
	assert.equal(first.lng, last.lng, 'the loop must close so the preview reads as a lap');
});

test('the demo track carries no timestamps or heart-rate samples', () => {
	// It is illustrative geometry, not a recording. Anything that looked
	// like real captured telemetry would invite reading it as one.
	for (const p of DEMO_TRACK) {
		assert.equal(p.ts, undefined);
		assert.equal(p.bpm, undefined);
	}
});

test('splits are consecutive kilometres at runnable paces', () => {
	DEMO_SPLITS.forEach((s, i) => {
		assert.equal(s.km, i + 1, 'splits must be consecutive and 1-indexed');
		assert.ok(s.seconds > 120 && s.seconds < 900, `implausible split ${s.seconds}s`);
	});
});

test('the split bar chart has a visible spread to render', () => {
	// A flat set would draw eight identical bars and say nothing about
	// the feature the card is selling.
	const secs = DEMO_SPLITS.map((s) => s.seconds);
	assert.ok(Math.max(...secs) - Math.min(...secs) >= 20, 'bars would look flat');
});

test('heart-rate zones are whole percentages summing to 100', () => {
	assert.equal(DEMO_HR_ZONES.length, 5, 'the product models five zones');
	for (const z of DEMO_HR_ZONES) {
		assert.ok(Number.isInteger(z) && z >= 0 && z <= 100, `bad zone share ${z}`);
	}
	assert.equal(
		DEMO_HR_ZONES.reduce((a, b) => a + b, 0),
		100,
		'the stacked bar must fill exactly',
	);
});

test('the headline figures agree with the splits they sit above', () => {
	// The defect these constants close: the markup read 8.04 km / 39:54 /
	// 4:58 per km over bars summing to 39:14 at 4:54. A visitor who reads
	// the split table — which is the visitor this card is FOR — can do that
	// arithmetic, so the three figures are derived and this is the check
	// that they still are.
	assert.equal(
		DEMO_TOTAL_SECONDS,
		DEMO_SPLITS.reduce((t, s) => t + s.seconds, 0),
		'the time is the sum of the bars or it is decoration',
	);
	assert.equal(DEMO_DISTANCE_KM, DEMO_SPLITS.length, 'each split is one kilometre');
	assert.equal(DEMO_PACE_SECONDS_PER_KM, DEMO_TOTAL_SECONDS / DEMO_DISTANCE_KM);
	// Every split is a kilometre inside the run, so the average pace has to
	// land between the quickest and the slowest of them.
	const secs = DEMO_SPLITS.map((s) => s.seconds);
	assert.ok(DEMO_PACE_SECONDS_PER_KM >= Math.min(...secs));
	assert.ok(DEMO_PACE_SECONDS_PER_KM <= Math.max(...secs));
});

test('the rendered labels are the shapes the card lays out for', () => {
	// The card gives each figure a fixed slot, so a label that grew an hours
	// field or a third decimal would overflow it rather than wrap.
	assert.match(DEMO_TIME_LABEL, /^\d{1,2}:[0-5]\d$/);
	assert.match(DEMO_PACE_LABEL, /^\d:[0-5]\d$/);
	assert.match(DEMO_DISTANCE_LABEL, /^\d+\.\d{2}$/);
});

test('the heart-rate trace covers the run at plausible, whole bpm', () => {
	// One a minute across the run the splits add up to.
	assert.equal(DEMO_HEART_RATE.length, Math.ceil(DEMO_TOTAL_SECONDS / 60));
	for (const bpm of DEMO_HEART_RATE) {
		assert.ok(Number.isInteger(bpm) && bpm >= 90 && bpm <= 200, `implausible ${bpm} bpm`);
	}
});

test('the heart-rate trace rises with the negative split', () => {
	// The splits get faster toward the end; a heart rate that fell over the
	// same stretch would contradict the chart beside it.
	const quarter = Math.floor(DEMO_HEART_RATE.length / 4);
	const mean = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;
	assert.ok(
		mean(DEMO_HEART_RATE.slice(-quarter)) > mean(DEMO_HEART_RATE.slice(quarter, -quarter)),
		'the closing quarter should run hotter than the middle',
	);
});

test('the elevation profile is a closed loop with a visible shape', () => {
	assert.ok(DEMO_ELEVATION.length >= 16, 'too few readings to draw a profile');
	assert.equal(DEMO_ELEVATION[0], DEMO_ELEVATION[DEMO_ELEVATION.length - 1], 'a loop ends where it starts');
	for (const m of DEMO_ELEVATION) assert.ok(Number.isFinite(m) && m >= 0 && m < 3000, `bad height ${m}`);
	assert.ok(Math.max(...DEMO_ELEVATION) - Math.min(...DEMO_ELEVATION) >= 10, 'the profile would draw flat');
});
