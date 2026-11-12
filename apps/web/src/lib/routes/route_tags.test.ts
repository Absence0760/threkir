import { test } from 'node:test';
import assert from 'node:assert/strict';
import { distinctTags } from './route_tags';

// Each case mirrors one in apps/backend/supabase/tests/routes_tags_distinct_test.sql,
// so the client read and the server write agree on what the set is.

test('duplicates and NULLs are dropped, each value kept at its first position', () => {
	assert.deepEqual(
		distinctTags(['trail', 'hills', 'trail', null, 'hills', 'loop']),
		['trail', 'hills', 'loop']
	);
});

test('equality is exact: values differing only in case are distinct', () => {
	assert.deepEqual(distinctTags(['Trail', 'trail']), ['Trail', 'trail']);
});

test('an absent or empty array reads as no tags', () => {
	assert.deepEqual(distinctTags(null), []);
	assert.deepEqual(distinctTags(undefined), []);
	assert.deepEqual(distinctTags([]), []);
});

test('the result is a fresh array, never the input', () => {
	const input = ['trail'];
	const out = distinctTags(input);
	assert.notEqual(out, input);
	out.push('hills');
	assert.deepEqual(input, ['trail']);
});
