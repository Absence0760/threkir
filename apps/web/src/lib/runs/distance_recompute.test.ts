import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	CURRENT_DISTANCE_ESTIMATOR,
	RECOMPUTABLE_SOURCES,
	canRecomputeDistance,
	classifyRecomputeError,
	mapMatchedDistanceM,
	recordedDistanceM,
	type RecomputeCandidate,
} from './distance_recompute';
import type { RunSource } from '../types';

const OWNER = '00000000-0000-0000-0000-000000000001';
const OTHER = '00000000-0000-0000-0000-000000000002';

function run(over: Partial<RecomputeCandidate> = {}): RecomputeCandidate {
	return {
		user_id: OWNER,
		source: 'app',
		track_url: `${OWNER}/run.json.gz`,
		metadata: { activity_type: 'run' },
		...over,
	};
}

test('the owner of an app-recorded tracked run may recompute', () => {
	assert.equal(canRecomputeDistance(run(), OWNER), true);
});

test('a watch-recorded run is recomputable too', () => {
	assert.equal(canRecomputeDistance(run({ source: 'watch' }), OWNER), true);
});

test('only our own recorders are recomputable sources', () => {
	assert.deepEqual([...RECOMPUTABLE_SOURCES].sort(), ['app', 'watch']);
	const imported: RunSource[] = ['healthkit', 'healthconnect', 'strava', 'garmin', 'parkrun', 'race'];
	for (const source of imported) {
		assert.equal(canRecomputeDistance(run({ source }), OWNER), false, source);
	}
});

test('a non-owner, or no viewer, is never offered the action', () => {
	assert.equal(canRecomputeDistance(run(), OTHER), false);
	assert.equal(canRecomputeDistance(run(), null), false);
	assert.equal(canRecomputeDistance(run(), undefined), false);
	assert.equal(canRecomputeDistance(null, OWNER), false);
});

test('a run with no stored track has nothing to recompute from', () => {
	assert.equal(canRecomputeDistance(run({ track_url: null }), OWNER), false);
	assert.equal(canRecomputeDistance(run({ track_url: '' }), OWNER), false);
});

test('any distance provenance tag blocks the recompute, as the worker skips it', () => {
	for (const tag of ['pedometer', 'treadmill', 'something_new']) {
		const candidate = run({ metadata: { distance_source: tag } });
		assert.equal(canRecomputeDistance(candidate, OWNER), false, tag);
	}
	assert.equal(canRecomputeDistance(run({ metadata: { distance_source: '' } }), OWNER), true);
	assert.equal(canRecomputeDistance(run({ metadata: { distance_source: 7 } }), OWNER), true);
});

test('an in-progress stub, a manual entry and an indoor run are never offered', () => {
	for (const key of ['in_progress', 'manual_entry', 'indoor', 'indoor_estimated']) {
		assert.equal(canRecomputeDistance(run({ metadata: { [key]: true } }), OWNER), false, key);
		assert.equal(canRecomputeDistance(run({ metadata: { [key]: false } }), OWNER), true, key);
		assert.equal(canRecomputeDistance(run({ metadata: { [key]: 'true' } }), OWNER), true, key);
	}
});

test('a run already on the current estimator is not offered again', () => {
	assert.equal(CURRENT_DISTANCE_ESTIMATOR, 'kalman_v2');
	assert.equal(
		canRecomputeDistance(run({ metadata: { distance_estimator: 'kalman_v2' } }), OWNER),
		false,
	);
	assert.equal(
		canRecomputeDistance(
			run({
				metadata: { distance_estimator: 'kalman_v2', distance_recomputed_at: '2026-10-08T08:00:00Z' },
			}),
			OWNER,
		),
		false,
	);
});

test('a run its recorder stamped live is not offered, whatever the estimator', () => {
	// The Wear OS and watchOS recorders stamp kalman_v1 on every run; the
	// worker skips a live stamp because the stored track is movement-gated.
	for (const estimator of ['kalman_v1', 'something_older']) {
		const candidate = run({ source: 'watch', metadata: { distance_estimator: estimator } });
		assert.equal(canRecomputeDistance(candidate, OWNER), false, estimator);
	}
	assert.equal(canRecomputeDistance(run({ metadata: { distance_estimator: null } }), OWNER), false);
});

test('a run a recompute stamped kalman_v1 (the v1.1 forward filter) is offered again', () => {
	assert.equal(
		canRecomputeDistance(
			run({
				source: 'watch',
				metadata: { distance_estimator: 'kalman_v1', distance_recomputed_at: '2026-10-08T08:00:00Z' },
			}),
			OWNER,
		),
		true,
	);
});

test('null metadata reads as an old, recomputable run', () => {
	assert.equal(canRecomputeDistance(run({ metadata: null }), OWNER), true);
});

test('recordedDistanceM returns only a usable positive number', () => {
	assert.equal(recordedDistanceM({ distance_recorded_m: 6309.4 }), 6309.4);
	assert.equal(recordedDistanceM({ distance_recorded_m: 0 }), null);
	assert.equal(recordedDistanceM({ distance_recorded_m: -3 }), null);
	assert.equal(recordedDistanceM({ distance_recorded_m: '6309' }), null);
	assert.equal(recordedDistanceM({}), null);
	assert.equal(recordedDistanceM(null), null);
	assert.equal(recordedDistanceM(undefined), null);
});

test('classifyRecomputeError maps the RPC refusals by SQLSTATE', () => {
	assert.equal(classifyRecomputeError({ code: '42501', message: 'not authorized' }), 'not_authorized');
	assert.equal(classifyRecomputeError({ code: '22000', message: 'no track' }), 'no_track');
	assert.equal(classifyRecomputeError({ code: '500', message: 'boom' }), 'other');
	assert.equal(classifyRecomputeError(new Error('network')), 'other');
	assert.equal(classifyRecomputeError(null), 'other');
});

test('mapMatchedDistanceM returns only a usable positive number', () => {
	assert.equal(mapMatchedDistanceM({ distance_map_matched_m: 4988.3 }), 4988.3);
	assert.equal(mapMatchedDistanceM({ distance_map_matched_m: 0 }), null);
	assert.equal(mapMatchedDistanceM({ distance_map_matched_m: -1 }), null);
	assert.equal(mapMatchedDistanceM({ distance_map_matched_m: '4988' }), null);
	assert.equal(mapMatchedDistanceM({}), null);
	assert.equal(mapMatchedDistanceM(null), null);
	assert.equal(mapMatchedDistanceM(undefined), null);
});
