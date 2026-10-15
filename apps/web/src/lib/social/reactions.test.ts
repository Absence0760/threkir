import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyReactionToggle, isReactionKey, REACTION_KEYS, reactionTallies } from './reactions';

test('REACTION_KEYS is the five-key whitelist the CHECK carries', () => {
	assert.deepEqual([...REACTION_KEYS], ['fire', 'strong', 'trophy', 'thumbs_up', 'wave']);
});

test('isReactionKey accepts only whitelisted strings', () => {
	assert.equal(isReactionKey('fire'), true);
	assert.equal(isReactionKey('heart_eyes'), false);
	assert.equal(isReactionKey(3), false);
});

test('reactionTallies: one tally per key in whitelist order, zero when unused', () => {
	const t = reactionTallies([{ reaction: 'wave', reaction_count: 2, viewer_reacted: true }]);
	assert.deepEqual(
		t.map((x) => [x.key, x.count, x.viewerReacted]),
		[
			['fire', 0, false],
			['strong', 0, false],
			['trophy', 0, false],
			['thumbs_up', 0, false],
			['wave', 2, true],
		],
	);
});

test('reactionTallies: drops an unknown key and clamps a bad count', () => {
	const t = reactionTallies([
		{ reaction: 'party', reaction_count: 9, viewer_reacted: true },
		{ reaction: 'fire', reaction_count: -3, viewer_reacted: false },
	]);
	assert.equal(t.length, 5);
	assert.equal(t[0].count, 0);
});

test('applyReactionToggle: a real add bumps the count and sets the flag', () => {
	const t = applyReactionToggle(reactionTallies([]), 'fire', true, true);
	assert.deepEqual([t[0].count, t[0].viewerReacted], [1, true]);
});

test('applyReactionToggle: a no-op flips the flag without moving the count', () => {
	const start = reactionTallies([{ reaction: 'fire', reaction_count: 1, viewer_reacted: false }]);
	const t = applyReactionToggle(start, 'fire', true, false);
	assert.deepEqual([t[0].count, t[0].viewerReacted], [1, true]);
});

test('applyReactionToggle: a real remove never goes below zero', () => {
	const t = applyReactionToggle(reactionTallies([]), 'wave', false, true);
	assert.deepEqual([t[4].count, t[4].viewerReacted], [0, false]);
});
