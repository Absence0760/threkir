import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	END_CARD_S,
	frameDurationUs,
	frameTimestampUs,
	isKeyFrame,
	MAX_FLIGHT_S,
	MIN_FLIGHT_S,
	videoFrame,
	videoTimeline,
} from './video_timeline.ts';

test('a short course still flies for the minimum, a long one is capped', () => {
	assert.equal(videoTimeline(500).flightFrames, MIN_FLIGHT_S * 30);
	assert.equal(videoTimeline(170_000).flightFrames, MAX_FLIGHT_S * 30);
	assert.equal(videoTimeline(3000).flightFrames, 12 * 30);
});

test('the end card adds its own seconds after the flight', () => {
	const t = videoTimeline(3000);
	assert.equal(t.endFrames, END_CARD_S * 30);
	assert.equal(t.totalFrames, t.flightFrames + t.endFrames);
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
	assert.deepEqual(videoFrame(t, t.flightFrames, 5000), { phase: 'end', dM: 5000, progress: 0 });
	assert.deepEqual(videoFrame(t, t.totalFrames - 1, 5000), { phase: 'end', dM: 5000, progress: 1 });
	assert.deepEqual(videoFrame(t, t.totalFrames + 50, 5000), videoFrame(t, t.totalFrames - 1, 5000));
});

test('the same index always gives the same frame', () => {
	const t = videoTimeline(12_345);
	assert.deepEqual(videoFrame(t, 77, 12_345), videoFrame(t, 77, 12_345));
});

test('timestamps are whole microseconds with no drift over a whole video', () => {
	assert.equal(frameTimestampUs(0, 30), 0);
	assert.equal(frameTimestampUs(1, 30), 33333);
	assert.equal(frameTimestampUs(2, 30), 66667);
	assert.equal(frameTimestampUs(690, 30), 23_000_000);
	let sum = 0;
	for (let i = 0; i < 690; i++) sum += frameDurationUs(i, 30);
	assert.equal(sum, 23_000_000);
});

test('a keyframe every two seconds, starting on the first frame', () => {
	assert.equal(isKeyFrame(0, 30), true);
	assert.equal(isKeyFrame(59, 30), false);
	assert.equal(isKeyFrame(60, 30), true);
});
