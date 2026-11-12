import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { play, seek, tick } from './playback.ts';

test('a tick advances at ground speed while playing', () => {
	assert.deepEqual(tick({ dM: 100, playing: true }, 1000, 250, 5000), { dM: 350, playing: true });
});

test('a paused flight does not move', () => {
	const s = { dM: 100, playing: false };
	assert.equal(tick(s, 1000, 250, 5000), s);
});

test('reaching the finish stops on the finish', () => {
	assert.deepEqual(tick({ dM: 4900, playing: true }, 1000, 250, 5000), { dM: 5000, playing: false });
});

test('play from the finish restarts at the start, otherwise resumes in place', () => {
	assert.deepEqual(play({ dM: 5000, playing: false }, 5000), { dM: 0, playing: true });
	assert.deepEqual(play({ dM: 1200, playing: false }, 5000), { dM: 1200, playing: true });
});

test('a zero-length course never plays', () => {
	assert.deepEqual(play({ dM: 0, playing: false }, 0), { dM: 0, playing: false });
});

test('seek clamps into the course and pauses', () => {
	assert.deepEqual(seek(-5, 5000), { dM: 0, playing: false });
	assert.deepEqual(seek(9000, 5000), { dM: 5000, playing: false });
	assert.deepEqual(seek(Number.NaN, 5000), { dM: 0, playing: false });
	assert.deepEqual(seek(2500, 5000), { dM: 2500, playing: false });
});
