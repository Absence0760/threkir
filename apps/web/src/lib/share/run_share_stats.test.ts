// Mirrors apps/mobile_android/test/run_share_stats_test.dart case for case.

import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import type { TrackPoint } from '../types';
import {
	RUN_SHARE_STAT_KINDS,
	availableShareStats,
	formatShareDuration,
	runShareClimbMetres,
	runShareStats,
	type RunShareStatLabels,
	type ShareableRun,
} from './run_share_stats';

const labels: RunShareStatLabels = {
	distance: 'Distance',
	pace: 'Pace',
	speed: 'Speed',
	time: 'Time',
	climb: 'Climb',
	heartRate: 'Avg HR',
	bpm: 'bpm',
};

const run = (over: Partial<ShareableRun> = {}): ShareableRun => ({
	distance_m: 10000,
	duration_s: 50 * 60,
	track: [],
	source: 'app',
	activity_type: 'run',
	metadata: {},
	...over,
});

const hill: TrackPoint[] = Array.from({ length: 6 }, (_, i) => ({
	lat: 51.44 + i * 0.002,
	lng: -0.27,
	ele: 20 + i * 30,
	ts: new Date(Date.UTC(2026, 3, 15, 8, i)).toISOString(),
}));

describe('availableShareStats', () => {
	test('distance, pace and time always; nothing unmeasured', () => {
		assert.deepEqual(availableShareStats(run()), ['distance', 'pace', 'time']);
	});

	test('climb when the track climbed, heart rate when it was measured', () => {
		assert.deepEqual(
			availableShareStats(run({ track: hill, metadata: { avg_bpm: 155 } })),
			[...RUN_SHARE_STAT_KINDS],
		);
	});

	test('a zero or absent average heart rate is not offered', () => {
		for (const metadata of [{ avg_bpm: 0 }, {}]) {
			assert.ok(!availableShareStats(run({ metadata })).includes('heartRate'));
		}
	});

	test('a flat track offers no climb', () => {
		const flat = Array.from({ length: 4 }, (_, i) => ({ lat: 51.44 + i * 0.002, lng: -0.27, ele: 20 }));
		assert.equal(runShareClimbMetres(run({ track: flat })), null);
	});
});

describe('runShareStats', () => {
	test('prints the picked kinds in display order', () => {
		const stats = runShareStats(labels, run(), 'km', { kinds: ['time', 'distance'], locale: 'en' });
		assert.deepEqual(stats.map((s) => s.kind), ['distance', 'time']);
		assert.equal(stats[0].value, '10.00');
		assert.equal(stats[1].value, '50:00');
	});

	test('a pick the run cannot print is dropped, never shown empty', () => {
		const stats = runShareStats(labels, run(), 'km', { kinds: ['heartRate', 'climb'] });
		assert.deepEqual(stats.map((s) => s.kind), ['distance']);
	});

	test('heart rate prints the measured average in bpm', () => {
		const [stat] = runShareStats(labels, run({ metadata: { avg_bpm: 151.6 } }), 'km', { kinds: ['heartRate'] });
		assert.equal(stat.value, '152');
		assert.equal(stat.unit, labels.bpm);
	});

	test('climb prints in the runner unit, without its label in the value', () => {
		const [km] = runShareStats(labels, run({ track: hill }), 'km', { kinds: ['climb'], locale: 'en' });
		const [mi] = runShareStats(labels, run({ track: hill }), 'mi', { kinds: ['climb'], locale: 'en' });
		assert.equal(km.unit, 'm');
		assert.equal(mi.unit, 'ft');
		assert.ok(!km.value.includes('m'));
		assert.ok(Number(mi.value.replaceAll(',', '')) > Number(km.value.replaceAll(',', '')));
	});

	test('moving time rounds a millisecond-stamped track to the second', () => {
		const track = [
			{ lat: 51.44, lng: -0.27, ts: '2026-04-15T08:00:00.000Z' },
			{ lat: 51.442, lng: -0.27, ts: '2026-04-15T08:00:01.600Z' },
		];
		const [stat] = runShareStats(labels, run({ track }), 'km', { kinds: ['time'] });
		assert.equal(stat.value, '00:02');
	});

	test('a ride prints speed in the pace slot', () => {
		const [stat] = runShareStats(labels, run({ activity_type: 'cycle' }), 'km', { kinds: ['pace'] });
		assert.equal(stat.label, labels.speed);
	});
});

test('formatShareDuration drops the hour under an hour', () => {
	assert.equal(formatShareDuration(4 * 60 + 5), '04:05');
	assert.equal(formatShareDuration(2 * 3600 + 3 * 60 + 4), '2:03:04');
});
