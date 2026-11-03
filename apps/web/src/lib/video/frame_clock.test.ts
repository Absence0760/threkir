import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { frameDurationUs, frameTimestampUs, isKeyFrame } from './frame_clock.ts';

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
