import { test } from 'node:test';
import assert from 'node:assert/strict';
import { HEART_RATE_METADATA_KEYS, hasHeartRate, stripHeartRate } from './heart_rate_consent';

// Twin of packages/core_models/test/heart_rate_consent_test.dart
// (decisions § 2513) — same cases, same count.

test('the heart-rate keys are avg_bpm, max_bpm, hr_coverage and hr_series_url', () => {
	assert.deepEqual([...HEART_RATE_METADATA_KEYS], ['avg_bpm', 'max_bpm', 'hr_coverage', 'hr_series_url']);
});

test('a run with no heart rate comes back unchanged', () => {
	const input = { metadata: { title: 'Easy' }, track: [{ lat: 1, lng: 2, ts: '2026-11-01T08:00:00Z' }] };
	assert.equal(hasHeartRate(input), false);
	assert.equal(stripHeartRate(input), input);
});

test('the heart-rate metadata keys go and every other key stays', () => {
	const input = {
		distance_m: 5000,
		metadata: { avg_bpm: 150, max_bpm: 181, hr_coverage: 0.9, hr_series_url: 'u/r1.hr.json.gz', title: 'Tempo' },
		hrSeries: [{ bpm: 150 }],
	};
	const out = stripHeartRate(input);
	assert.deepEqual(out.metadata, { title: 'Tempo' });
	assert.equal(out.distance_m, 5000);
	assert.equal(out.hrSeries, undefined);
	assert.equal(input.metadata.avg_bpm, 150, 'the input is not mutated');
});

test('per-point bpm goes and every other point field stays', () => {
	const out = stripHeartRate({
		track: [
			{ lat: 1, lng: 2, ele: 30, ts: '2026-11-01T08:00:00Z', bpm: 140 },
			{ lat: 1.1, lng: 2.1, ts: '2026-11-01T08:00:00Z' },
		],
	});
	assert.deepEqual(out.track, [
		{ lat: 1, lng: 2, ele: 30, ts: '2026-11-01T08:00:00Z' },
		{ lat: 1.1, lng: 2.1, ts: '2026-11-01T08:00:00Z' },
	]);
});

test('a bpm on the track alone counts as heart rate', () => {
	assert.equal(hasHeartRate({ track: [{ bpm: 99 }] }), true);
});
