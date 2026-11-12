import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { MIN_CARD_OPAQUE_FRACTION, isCompleteCardCapture, opaqueFraction } from './share_card_capture.ts';

function pixels(alphas: number[]): Uint8ClampedArray {
	const out = new Uint8ClampedArray(alphas.length * 4);
	alphas.forEach((a, i) => {
		out[i * 4] = 200;
		out[i * 4 + 3] = a;
	});
	return out;
}

describe('share card capture check', () => {
	test('an opaque capture is complete', () => {
		const rgba = pixels(Array(100).fill(255));
		assert.equal(opaqueFraction(rgba), 1);
		assert.equal(isCompleteCardCapture(rgba), true);
	});

	test('a fully transparent capture, the off-screen clone, is not', () => {
		const rgba = pixels(Array(100).fill(0));
		assert.equal(opaqueFraction(rgba), 0);
		assert.equal(isCompleteCardCapture(rgba), false);
	});

	test('a card drawn partly outside its frame is not', () => {
		const rgba = pixels([...Array(90).fill(255), ...Array(10).fill(0)]);
		assert.equal(opaqueFraction(rgba), 0.9);
		assert.equal(isCompleteCardCapture(rgba), false);
	});

	test('the threshold counts near-opaque pixels and sits at 99%', () => {
		assert.equal(MIN_CARD_OPAQUE_FRACTION, 0.99);
		assert.equal(isCompleteCardCapture(pixels([...Array(99).fill(250), 0])), true);
		assert.equal(isCompleteCardCapture(pixels([...Array(98).fill(255), 249, 0])), false);
	});

	test('no pixels at all is not a capture', () => {
		assert.equal(opaqueFraction(new Uint8ClampedArray(0)), 0);
		assert.equal(isCompleteCardCapture(new Uint8ClampedArray(3)), false);
	});
});
