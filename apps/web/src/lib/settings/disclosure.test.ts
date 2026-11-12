import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	DISCLOSURE_FULL_RUNS,
	DISCLOSURE_LEVEL_KEY,
	DISCLOSURE_LEVELS,
	DISCLOSURE_STANDARD_RUNS,
	disclosureLevel,
	isDisclosureLevel,
	resolveDisclosureLevel,
} from './disclosure';
import { PRIMARY_GOAL_VALUES } from './onboarding';

/// Mirror of `apps/mobile_android/test/disclosure_test.dart` — same cases,
/// same count.

test('DISCLOSURE_LEVEL_KEY is the universal-prefs bag key the override lives in', () => {
	assert.equal(DISCLOSURE_LEVEL_KEY, 'disclosure_level');
});

test('DISCLOSURE_LEVELS is the three levels, ordered least to most', () => {
	// The index is the rank, so the order is load-bearing, not cosmetic.
	assert.deepEqual([...DISCLOSURE_LEVELS], ['simple', 'standard', 'full']);
});

test('a fresh account lands on the floor its stated goal puts under it', () => {
	// Zero runs, so the history floor is `simple` and the goal alone decides.
	assert.equal(disclosureLevel('general_fitness', 0), 'simple');
	assert.equal(disclosureLevel('weight_loss', 0), 'simple');
	assert.equal(disclosureLevel('5k', 0), 'simple');
	assert.equal(disclosureLevel('10k', 0), 'standard');
	assert.equal(disclosureLevel('half_marathon', 0), 'standard');
	assert.equal(disclosureLevel('marathon', 0), 'full');
	// And every goal the wizard can write resolves to a real level.
	for (const goal of PRIMARY_GOAL_VALUES) {
		assert.ok(isDisclosureLevel(disclosureLevel(goal, 0)), goal);
	}
});

test('history alone raises the level at each threshold', () => {
	assert.equal(disclosureLevel('5k', DISCLOSURE_STANDARD_RUNS - 1), 'simple');
	assert.equal(disclosureLevel('5k', DISCLOSURE_STANDARD_RUNS), 'standard');
	assert.equal(disclosureLevel('5k', DISCLOSURE_FULL_RUNS - 1), 'standard');
	assert.equal(disclosureLevel('5k', DISCLOSURE_FULL_RUNS), 'full');
	assert.equal(disclosureLevel('5k', 4000), 'full');
});

test('the higher of the two floors wins, in both directions', () => {
	// Goal above history.
	assert.equal(disclosureLevel('marathon', 0), 'full');
	assert.equal(disclosureLevel('10k', 0), 'standard');
	// History above goal.
	assert.equal(disclosureLevel('general_fitness', DISCLOSURE_FULL_RUNS), 'full');
	// Neither above the other.
	assert.equal(disclosureLevel('10k', DISCLOSURE_STANDARD_RUNS), 'standard');
	// A big history never drags a high goal back DOWN.
	assert.equal(disclosureLevel('marathon', 1), 'full');
});

test('an unset or unknown goal leaves the history floor to decide alone', () => {
	for (const goal of [null, undefined, '', 'ultra', '10K', 'PRIMARY_GOAL_VALUES', '__proto__']) {
		assert.equal(disclosureLevel(goal, 0), 'simple', String(goal));
		assert.equal(disclosureLevel(goal, DISCLOSURE_STANDARD_RUNS), 'standard', String(goal));
		assert.equal(disclosureLevel(goal, DISCLOSURE_FULL_RUNS), 'full', String(goal));
	}
});

test('a run count that is not a whole positive number reads as zero', () => {
	// A count comes off a `count: 'exact'` read that can degrade; it must not
	// mint a level out of a negative or a NaN.
	for (const runs of [-1, -4000, Number.NaN, Number.NEGATIVE_INFINITY]) {
		assert.equal(disclosureLevel('5k', runs), 'simple', String(runs));
	}
	// A fraction floors rather than rounds up over a threshold.
	assert.equal(disclosureLevel('5k', DISCLOSURE_STANDARD_RUNS - 0.5), 'simple');
	assert.equal(disclosureLevel('5k', Number.POSITIVE_INFINITY), 'simple');
});

test('isDisclosureLevel accepts exactly the three levels', () => {
	for (const level of DISCLOSURE_LEVELS) assert.ok(isDisclosureLevel(level), level);
	for (const other of [null, undefined, '', 'SIMPLE', 'basic', 0, 2, true, {}, ['full']]) {
		assert.ok(!isDisclosureLevel(other), String(other));
	}
});

test('a stored level is what the surface renders at, whatever the derivation says', () => {
	// The override is the whole reason hiding anything is safe.
	assert.equal(resolveDisclosureLevel('simple', 'marathon', 4000), 'simple');
	assert.equal(resolveDisclosureLevel('full', 'general_fitness', 0), 'full');
	assert.equal(resolveDisclosureLevel('standard', null, 0), 'standard');
});

test('any value that is not a level falls through to the derivation', () => {
	for (const stored of [null, undefined, '', 'basics', 'SIMPLE', 1, false, {}]) {
		assert.equal(resolveDisclosureLevel(stored, 'marathon', 0), 'full', String(stored));
		assert.equal(resolveDisclosureLevel(stored, 'general_fitness', 0), 'simple', String(stored));
	}
});
