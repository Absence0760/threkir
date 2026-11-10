import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
	DM_REACTIONS,
	DM_REACTION_CODEPOINTS,
	dmReactionGlyph,
	myDmReaction,
	parseDmReaction,
	summarizeDmReactions,
	withMyDmReaction,
} from './dm_reactions.ts';

test('the keys are the ones the reactions CHECK admits, in its order', () => {
	const dir = fileURLToPath(new URL('../../../../backend/supabase/migrations/', import.meta.url));
	const file = readdirSync(dir).find((f) => f.endsWith('_dm_reactions.sql'));
	assert.ok(file, 'the dm_reactions migration is missing — re-anchor');
	const sql = readFileSync(dir + file, 'utf8');
	const m = sql.match(/check \(reaction in \(([^)]*)\)\)/);
	assert.ok(m, 'the reaction CHECK was not found — re-anchor');
	const keys = [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]);
	assert.deepEqual(keys, [...DM_REACTIONS]);
});

test('every key draws from codepoints, never from a stored glyph', () => {
	for (const key of DM_REACTIONS) {
		const glyph = dmReactionGlyph(key);
		assert.deepEqual([...glyph].map((c) => c.codePointAt(0)), [...DM_REACTION_CODEPOINTS[key]]);
	}
	assert.equal(dmReactionGlyph('thumbs_up').codePointAt(0), 0x1f44d);
});

test('parseDmReaction keeps only known keys', () => {
	assert.equal(parseDmReaction('heart'), 'heart');
	assert.equal(parseDmReaction('poop'), null);
	assert.equal(parseDmReaction(String.fromCodePoint(0x1f44d)), null);
	assert.equal(parseDmReaction(null), null);
});

const rows = [
	{ message_id: 'm1', user_id: 'me', reaction: 'fire' },
	{ message_id: 'm1', user_id: 'them', reaction: 'thumbs_up' },
	{ message_id: 'm2', user_id: 'them', reaction: 'fire' },
	{ message_id: 'm1', user_id: 'x', reaction: 'bogus' },
];

test('the summary counts per key in set order and marks the viewer', () => {
	assert.deepEqual(summarizeDmReactions(rows, 'm1', 'me'), [
		{ reaction: 'thumbs_up', count: 1, mine: false },
		{ reaction: 'fire', count: 1, mine: true },
	]);
	assert.deepEqual(summarizeDmReactions(rows, 'm1', null), [
		{ reaction: 'thumbs_up', count: 1, mine: false },
		{ reaction: 'fire', count: 1, mine: false },
	]);
	assert.deepEqual(summarizeDmReactions(rows, 'none', 'me'), []);
	assert.deepEqual(
		summarizeDmReactions(
			[
				{ message_id: 'm', user_id: 'a', reaction: 'sad' },
				{ message_id: 'm', user_id: 'b', reaction: 'sad' },
			],
			'm',
			'b',
		),
		[{ reaction: 'sad', count: 2, mine: true }],
	);
});

test('the viewer has at most one reaction per message', () => {
	assert.equal(myDmReaction(rows, 'm1', 'me'), 'fire');
	assert.equal(myDmReaction(rows, 'm2', 'me'), null);
	assert.equal(myDmReaction(rows, 'm1', undefined), null);
});

test('setting replaces the viewer row and clearing removes it', () => {
	const make = (reaction: string) => ({ message_id: 'm1', user_id: 'me', reaction });
	const set = withMyDmReaction(rows, 'm1', 'me', 'heart', make);
	assert.equal(myDmReaction(set, 'm1', 'me'), 'heart');
	assert.equal(set.filter((r) => r.message_id === 'm1' && r.user_id === 'me').length, 1);
	const cleared = withMyDmReaction(set, 'm1', 'me', null, make);
	assert.equal(myDmReaction(cleared, 'm1', 'me'), null);
	assert.equal(cleared.length, rows.length - 1);
});
