// Persona-hunt Round 2 finding Pro #3: the coach context shipped
// raw `metadata` jsonb to Anthropic. This file pins the
// `pickAllowedRunMetadata` allowlist so adding a sensitive key
// without explicit review surfaces here.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { pickAllowedRunMetadata } from './context';

test('pickAllowedRunMetadata — null input returns null', () => {
	assert.equal(pickAllowedRunMetadata(null, true), null);
});

test('pickAllowedRunMetadata — empty input returns null', () => {
	assert.equal(pickAllowedRunMetadata({}, true), null);
});

test('pickAllowedRunMetadata — keeps coaching-value keys (consent granted)', () => {
	const meta = {
		avg_bpm: 152,
		workout_kind: 'tempo',
		manual_completion: true,
		is_indoor: false,
		elevation_m: 120,
	};
	const out = pickAllowedRunMetadata(meta, true);
	assert.deepEqual(out, meta);
});

test('pickAllowedRunMetadata — strips avg_bpm when health consent is absent', () => {
	// avg_bpm is Art 9(2)(a) heart-rate. Without health-data consent it
	// must never cross the Anthropic sub-processor boundary; non-health
	// keys still pass through.
	const meta = {
		is_indoor: false,
		avg_bpm: 152,
		elevation_m: 120,
	};
	assert.deepEqual(pickAllowedRunMetadata(meta, false), {
		is_indoor: false,
		elevation_m: 120,
	});
	// With consent, the same input keeps avg_bpm.
	assert.deepEqual(pickAllowedRunMetadata(meta, true), meta);
});

test('pickAllowedRunMetadata — avg_bpm-only metadata returns null without consent', () => {
	// When the only allowlisted key is the gated HR field, the whole
	// metadata object collapses to null (self-hiding, compact payload).
	assert.equal(pickAllowedRunMetadata({ avg_bpm: 152 }, false), null);
	assert.deepEqual(pickAllowedRunMetadata({ avg_bpm: 152 }, true), { avg_bpm: 152 });
});

test('pickAllowedRunMetadata — drops free-form notes', () => {
	// `notes` is a free-form field — anything the runner typed.
	// Realistic exposure for a user who pasted a journal entry.
	const out = pickAllowedRunMetadata({
		is_indoor: false,
		notes: 'felt awful, fight with partner before run, considered quitting',
	}, true);
	assert.deepEqual(out, { is_indoor: false });
});

test('pickAllowedRunMetadata — drops parkrun event + position', () => {
	// parkrun event id + finishing position is identifying info
	// against parkrun's own public results pages — leaks runner's
	// real-world identity into the model.
	const out = pickAllowedRunMetadata({
		is_indoor: false,
		event: 'bushy-2026-04-15',
		position: 42,
	}, true);
	assert.deepEqual(out, { is_indoor: false });
});

test('pickAllowedRunMetadata — drops external integration ids', () => {
	const out = pickAllowedRunMetadata({
		is_indoor: false,
		strava_id: '12345678',
		garmin_id: 'abc-def-123',
		health_connect_type: 'EXERCISE_SESSION',
		imported_from: 'strava',
		external_id: 'strava:12345678',
	}, true);
	assert.deepEqual(out, { is_indoor: false });
});

test('pickAllowedRunMetadata — drops internal owner-only flags', () => {
	const out = pickAllowedRunMetadata({
		is_indoor: false,
		created_by_user_id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
		recovered_from_crash: true,
		// owner-only by docs/backend/metadata.md classification
	}, true);
	assert.deepEqual(out, { is_indoor: false });
});

test('pickAllowedRunMetadata — drops raw laps array', () => {
	// `laps` is a list of per-lap stats — useful client-side, but the
	// coach doesn't read it (workout_step_results is the structured
	// version that's allowlisted instead).
	const out = pickAllowedRunMetadata({
		is_indoor: false,
		laps: [
			{ distance_m: 1000, duration_s: 240 },
			{ distance_m: 1000, duration_s: 245 },
		],
	}, true);
	assert.deepEqual(out, { is_indoor: false });
});

test('pickAllowedRunMetadata — entirely unallowlisted input returns null', () => {
	const out = pickAllowedRunMetadata({
		notes: 'private',
		strava_id: '99',
		external_id: 'strava:99',
	}, true);
	assert.equal(out, null);
});

test('pickAllowedRunMetadata — workout_step_results passes through (planned vs actual)', () => {
	// Per-step structured-workout adherence — explicit coaching
	// signal. Allowlisted intentionally.
	const meta = {
		workout_step_results: [
			{ kind: 'interval', target: 240, actual: 245 },
			{ kind: 'recovery', target: 360, actual: 358 },
		],
	};
	assert.deepEqual(pickAllowedRunMetadata(meta, true), meta);
});

test('pickAllowedRunMetadata — drops a legacy metadata.activity_type', () => {
	// The key moved to the runs.activity_type column (migration
	// 20261207_001), which the Coach selects; a copy still sitting in an
	// older row's bag would only send the same value twice.
	assert.equal(pickAllowedRunMetadata({ activity_type: 'run' }, true), null);
});
