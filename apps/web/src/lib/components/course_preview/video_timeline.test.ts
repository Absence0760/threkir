import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	END_CARD_S,
	MAX_FLIGHT_S,
	MIN_FLIGHT_S,
	VIDEO_FINALE,
	videoFlightSpeedMps,
	videoFrame,
	videoTimeline,
} from './video_timeline.ts';

test('a short course still flies for the minimum, a long one is capped', () => {
	assert.equal(videoTimeline(500).flightFrames, MIN_FLIGHT_S * 30);
	assert.equal(videoTimeline(170_000).flightFrames, MAX_FLIGHT_S * 30);
	assert.equal(videoTimeline(3000).flightFrames, 12 * 30);
});

test('the overview and the end card add their own seconds after the flight', () => {
	const t = videoTimeline(3000);
	assert.equal(t.overviewFrames, 5 * 30);
	assert.equal(t.endFrames, END_CARD_S * 30);
	assert.equal(t.totalFrames, t.flightFrames + t.overviewFrames + t.endFrames);
});

test('the video always carries the full ending, orbit included', () => {
	assert.ok(VIDEO_FINALE.easeMs > 0);
	assert.ok(VIDEO_FINALE.orbitDeg > 0);
});

test('overview frames hold the finish and step the ending clock to its last pose', () => {
	const t = videoTimeline(5000);
	assert.deepEqual(videoFrame(t, t.flightFrames, 5000), { phase: 'overview', dM: 5000, tMs: 1000 / 30 });
	const last = videoFrame(t, t.flightFrames + t.overviewFrames - 1, 5000);
	assert.equal(last.phase, 'overview');
	assert.ok(last.phase === 'overview' && Math.abs(last.tMs - (VIDEO_FINALE.easeMs + VIDEO_FINALE.orbitMs)) < 1e-9);
});

test('the flight starts on the start and its last frame is the finish', () => {
	const t = videoTimeline(5000);
	assert.deepEqual(videoFrame(t, 0, 5000), { phase: 'flight', dM: 0, progress: 0 });
	assert.deepEqual(videoFrame(t, t.flightFrames - 1, 5000), { phase: 'flight', dM: 5000, progress: 1 });
	const mid = videoFrame(t, (t.flightFrames - 1) / 2, 5000);
	assert.equal(mid.phase, 'flight');
	assert.ok(Math.abs(mid.dM - 2500) < 10);
});

test('end-card frames hold the finish and run their own progress to 1', () => {
	const t = videoTimeline(5000);
	assert.deepEqual(videoFrame(t, t.flightFrames + t.overviewFrames, 5000), { phase: 'end', dM: 5000, progress: 0 });
	assert.deepEqual(videoFrame(t, t.totalFrames - 1, 5000), { phase: 'end', dM: 5000, progress: 1 });
	assert.deepEqual(videoFrame(t, t.totalFrames + 50, 5000), videoFrame(t, t.totalFrames - 1, 5000));
});

test('the same index always gives the same frame', () => {
	const t = videoTimeline(12_345);
	assert.deepEqual(videoFrame(t, 77, 12_345), videoFrame(t, 77, 12_345));
});

test('the flight speed is the distance one flight frame covers, per second', () => {
	for (const totalM of [5000, 21_097.5, 50_000]) {
		const t = videoTimeline(totalM);
		const speed = videoFlightSpeedMps(t, totalM);
		const step = videoFrame(t, 1, totalM).dM - videoFrame(t, 0, totalM).dM;
		assert.ok(Math.abs(speed - step * t.fps) < 1e-6, `${totalM} m`);
	}
	assert.ok(Math.abs(videoFlightSpeedMps(videoTimeline(5000), 5000) - 250) < 1);
	assert.ok(Math.abs(videoFlightSpeedMps(videoTimeline(50_000), 50_000) - 2500) < 5);
	assert.equal(videoFlightSpeedMps(videoTimeline(0), 0), 0);
});
