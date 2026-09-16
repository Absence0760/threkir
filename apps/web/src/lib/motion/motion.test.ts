import { test } from 'node:test';
import assert from 'node:assert/strict';
import { easeOutCubic, parseReading, readingAt, staggerDelay, tickClock } from './motion';

test('easeOutCubic is clamped and lands on its ends', () => {
	assert.equal(easeOutCubic(-1), 0);
	assert.equal(easeOutCubic(0), 0);
	assert.equal(easeOutCubic(1), 1);
	assert.equal(easeOutCubic(3), 1);
	assert.ok(easeOutCubic(0.5) > 0.5, 'decelerates: past halfway at half time');
});

test('staggerDelay steps then caps', () => {
	assert.equal(staggerDelay(0), 0);
	assert.equal(staggerDelay(2), 140);
	assert.equal(staggerDelay(50), 420);
	assert.equal(staggerDelay(-3), 0);
});

test('parseReading recognises clocks and decimals, and nothing else', () => {
	assert.deepEqual(parseReading('39:54'), { kind: 'clock', parts: [39, 54], widths: [2, 2] });
	assert.deepEqual(parseReading('1:02:07'), { kind: 'clock', parts: [1, 2, 7], widths: [1, 2, 2] });
	assert.deepEqual(parseReading(' 8.04 '), { kind: 'decimal', value: 8.04, decimals: 2 });
	assert.deepEqual(parseReading('12'), { kind: 'decimal', value: 12, decimals: 0 });
	for (const text of ['', 'km', '4:5', '8.04km', '-3', '1:2:3:4']) {
		assert.equal(parseReading(text), null, text);
	}
});

test('readingAt keeps the final shape at every step', () => {
	assert.equal(readingAt('8.04', 0), '0.00');
	assert.equal(readingAt('8.04', 0.5), '4.02');
	assert.equal(readingAt('39:54', 0), '0:00');
	assert.equal(readingAt('39:54', 0.5), '19:57');
	assert.equal(readingAt('1:02:07', 0.5), '0:31:03');
	for (let i = 0; i <= 20; i++) {
		assert.match(readingAt('4:58', i / 20), /^\d+:\d{2}$/);
	}
});

test('readingAt returns the markup text verbatim once finished', () => {
	assert.equal(readingAt('39:54', 1), '39:54');
	assert.equal(readingAt('8.04', 1.4), '8.04');
	assert.equal(readingAt('n/a', 0.3), 'n/a');
});

test('tickClock rolls minutes and grows into hours', () => {
	assert.equal(tickClock('24:17'), '24:18');
	assert.equal(tickClock('24:59'), '25:00');
	assert.equal(tickClock('59:59'), '1:00:00');
	assert.equal(tickClock('1:00:59'), '1:01:00');
	assert.equal(tickClock('8.04'), '8.04');
});
