// Mirrors apps/mobile_android/test/pr_card_test.dart case for case.

import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import {
	PR_BRACKETS,
	PR_BRACKET_METRES,
	formatPrImprovement,
	prCardEntries,
	prImprovementSeconds,
} from './pr_card';

describe('prCardEntries', () => {
	test('no rows → no entries', () => {
		assert.deepEqual(prCardEntries([], []), []);
	});

	test('an improvement carries the time it beat', () => {
		const [e] = prCardEntries([{ distance: '5k', best_time_s: 1440, previous_time_s: 1500 }], []);
		assert.deepEqual(e, { distance: '5k', timeS: 1440, previousS: 1500, kind: 'improved' });
	});

	test('an improvement with no previous time is a first', () => {
		const [e] = prCardEntries([{ distance: '10k', best_time_s: 2900, previous_time_s: null }], []);
		assert.equal(e.kind, 'first');
		assert.equal(e.previousS, null);
	});

	test('a held record with no log row is held, with no previous time', () => {
		const [e] = prCardEntries([], [{ distance: 'marathon', best_time_s: 12000 }]);
		assert.deepEqual(e, { distance: 'marathon', timeS: 12000, previousS: null, kind: 'held' });
	});

	test('the log wins over the cache row for the same bracket', () => {
		const entries = prCardEntries(
			[{ distance: '5k', best_time_s: 1440, previous_time_s: 1500 }],
			[{ distance: '5k', best_time_s: 1440 }],
		);
		assert.equal(entries.length, 1);
		assert.equal(entries[0].kind, 'improved');
	});

	test('brackets are ordered longest first', () => {
		const entries = prCardEntries(
			[
				{ distance: '1_mile', best_time_s: 380, previous_time_s: 400 },
				{ distance: '10k', best_time_s: 2900, previous_time_s: null },
			],
			[{ distance: '5k', best_time_s: 1400 }],
		);
		assert.deepEqual(
			entries.map((e) => e.distance),
			['10k', '5k', '1_mile'],
		);
	});

	test('an unknown bracket and a non-positive time are dropped', () => {
		const entries = prCardEntries(
			[
				{ distance: '50k', best_time_s: 18000, previous_time_s: null },
				{ distance: '5k', best_time_s: 0, previous_time_s: null },
			],
			[{ distance: 'half_marathon', best_time_s: -1 }],
		);
		assert.deepEqual(entries, []);
	});

	test('a previous time no slower than the new one is not an improvement', () => {
		const [e] = prCardEntries([{ distance: '5k', best_time_s: 1500, previous_time_s: 1500 }], []);
		assert.equal(e.kind, 'first');
		assert.equal(e.previousS, null);
	});
});

describe('improvement', () => {
	test('seconds faster and its printed form', () => {
		const [e] = prCardEntries([{ distance: '5k', best_time_s: 1440, previous_time_s: 1482 }], []);
		assert.equal(prImprovementSeconds(e), 42);
		assert.equal(formatPrImprovement(e), '00:42');
	});

	test('an hour-long improvement prints hours', () => {
		const [e] = prCardEntries([{ distance: 'marathon', best_time_s: 12000, previous_time_s: 15700 }], []);
		assert.equal(formatPrImprovement(e), '1:01:40');
	});

	test('nothing beaten → null', () => {
		const [e] = prCardEntries([], [{ distance: '5k', best_time_s: 1400 }]);
		assert.equal(prImprovementSeconds(e), null);
		assert.equal(formatPrImprovement(e), null);
	});
});

describe('brackets', () => {
	test('every bracket has a distance, strictly increasing in declaration order', () => {
		const metres = PR_BRACKETS.map((b) => PR_BRACKET_METRES[b]);
		for (let i = 1; i < metres.length; i++) assert.ok(metres[i] > metres[i - 1]);
	});
});
