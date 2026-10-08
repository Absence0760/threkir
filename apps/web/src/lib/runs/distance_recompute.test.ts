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

test('a pedometer distance is not recomputable, a treadmill tag is no blocker by itself', () => {
	assert.equal(
		canRecomputeDistance(run({ metadata: { distance_source: 'pedometer' } }), OWNER),
		false,
	);
	assert.equal(
		canRecomputeDistance(run({ metadata: { distance_source: 'treadmill' } }), OWNER),
		true,
	);
});

test('a run already on the current estimator is not offered again', () => {
	assert.equal(CURRENT_DISTANCE_ESTIMATOR, 'kalman_v1');
	assert.equal(
		canRecomputeDistance(run({ metadata: { distance_estimator: 'kalman_v1' } }), OWNER),
		false,
	);
	assert.equal(
		canRecomputeDistance(run({ metadata: { distance_estimator: 'something_older' } }), OWNER),
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
