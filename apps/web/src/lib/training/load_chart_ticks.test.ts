import { test } from 'node:test';
import assert from 'node:assert/strict';
import { trainingLoadTickStep, trainingLoadTickValues } from './load_chart_ticks.ts';

// Spans from a single 10 s run (a fraction of a point) to a heavy training
// block, on ranges that straddle zero the way TSB does and ones that don't.
// Hand-picked spans are how the 0..2 band that crashed /dashboard went
// untested (#1155), so this walks the whole ladder instead.
function sweep(): Array<[number, number]> {
	const out: Array<[number, number]> = [];
	for (let exp = -6; exp <= 6; exp++) {
		for (const m of [1, 1.3, 2, 2.5, 3.9, 5, 7.7]) {
			const span = m * 10 ** exp;
			out.push([0, span], [-span / 2, span / 2], [-span, span * 0.1], [span * 3, span * 4]);
		}
	}
	return out;
}

test('trainingLoadTickStep walks the 1 / 2 / 5 x 10^n ladder', () => {
	assert.equal(trainingLoadTickStep(4), 1);
	assert.equal(trainingLoadTickStep(40), 10);
	assert.equal(trainingLoadTickStep(60), 20);
	assert.equal(trainingLoadTickStep(160), 50);
	assert.equal(trainingLoadTickStep(400), 100);
});

test('trainingLoadTickStep never steps below 1, and survives a degenerate span', () => {
	for (const span of [1e-9, 0.01, 0.4, 1, 2, 2.3, 3.9]) {
		assert.ok(trainingLoadTickStep(span) >= 1, `span ${span}`);
	}
	for (const span of [0, -5, Number.NaN, Number.POSITIVE_INFINITY]) {
		assert.equal(trainingLoadTickStep(span), 1, `span ${span}`);
	}
});

test('the near-zero range that crashed /dashboard yields -1, 0, 1', () => {
	// With a 0.5 step these keyed as [-1, -0, 0, 1, 1].
	assert.deepEqual(trainingLoadTickValues(-1, 1), [-1, 0, 1]);
});

test('every swept range gives distinct, ascending whole-number ticks inside it', () => {
	for (const [min, max] of sweep()) {
		const ticks = trainingLoadTickValues(min, max);
		const where = `[${min}, ${max}] -> ${JSON.stringify(ticks)}`;
		assert.ok(ticks.length <= 6, `too many ticks ${where}`);
		for (const [i, v] of ticks.entries()) {
			assert.ok(Number.isInteger(v), `non-integer ${where}`);
			assert.ok(!Object.is(v, -0), `-0 ${where}`);
			assert.ok(v >= Math.floor(min) && v <= Math.ceil(max), `outside ${where}`);
			if (i > 0) assert.ok(v > ticks[i - 1], `not strictly ascending ${where}`);
		}
	}
});

test('trainingLoadTickValues returns nothing for an unusable range', () => {
	assert.deepEqual(trainingLoadTickValues(Number.NaN, 5), []);
	assert.deepEqual(trainingLoadTickValues(0, Number.POSITIVE_INFINITY), []);
	assert.deepEqual(trainingLoadTickValues(5, 1), []);
});
