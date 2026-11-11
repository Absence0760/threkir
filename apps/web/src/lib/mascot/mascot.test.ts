import { test } from 'node:test';
import assert from 'node:assert/strict';

import { mascotShownIn, pickMilestone, type MilestoneFacts } from './mascot.ts';

const base: MilestoneFacts = { totalRuns: 12, runDistanceM: 6000, longestRunM: 21100, records: [], badgeEarned: false };

test('show_mascot hides him only on a literal false', () => {
	assert.equal(mascotShownIn({ universal: {}, device: {} }), true);
	assert.equal(mascotShownIn({ universal: { show_mascot: false }, device: {} }), false);
	assert.equal(mascotShownIn({ universal: { show_mascot: 'false' }, device: {} }), true);
	assert.equal(mascotShownIn({ universal: { show_mascot: true }, device: { show_mascot: false } }), false);
});

test('a plain run earns no milestone', () => {
	assert.equal(pickMilestone(base), null);
});

test('the first run outranks everything it also is', () => {
	assert.equal(
		pickMilestone({ ...base, totalRuns: 1, runDistanceM: 5000, longestRunM: 5000, records: [{ distance: '5k', kind: 'first' }], badgeEarned: true }),
		'first_run',
	);
});

test('the first 5K is a 5k record of kind first, ahead of a badge', () => {
	assert.equal(pickMilestone({ ...base, records: [{ distance: '5k', kind: 'first' }], badgeEarned: true }), 'first_5k');
	assert.equal(pickMilestone({ ...base, records: [{ distance: '10k', kind: 'first' }] }), null);
});

test('a badge, then a new best, then the longest run', () => {
	assert.equal(pickMilestone({ ...base, badgeEarned: true, records: [{ distance: '10k', kind: 'improved' }] }), 'badge');
	assert.equal(pickMilestone({ ...base, records: [{ distance: '10k', kind: 'improved' }] }), 'best');
	assert.equal(pickMilestone({ ...base, records: [{ distance: '10k', kind: 'held' }] }), null);
	assert.equal(pickMilestone({ ...base, runDistanceM: 21100 }), 'longest');
	assert.equal(pickMilestone({ ...base, runDistanceM: 0, longestRunM: 0 }), null);
});
