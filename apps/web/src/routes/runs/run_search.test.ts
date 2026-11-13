import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { runMatchesQuery } from './run_search';

test('a blank search matches every run, named or not', () => {
	assert.equal(runMatchesQuery({ title: 'Morning loop' }, ''), true);
	assert.equal(runMatchesQuery({ title: 'Morning loop' }, '   '), true);
	assert.equal(runMatchesQuery(null, ''), true);
});

test('the search matches part of the name, ignoring case and accents', () => {
	assert.equal(runMatchesQuery({ title: 'Morning Loop' }, 'loop'), true);
	assert.equal(runMatchesQuery({ title: 'Café run' }, 'cafe'), true);
	assert.equal(runMatchesQuery({ title: 'cafe run' }, 'CAFÉ'), true);
	assert.equal(runMatchesQuery({ title: 'Morning loop' }, '  morning  '), true);
});

test('a name that does not contain the search does not match', () => {
	assert.equal(runMatchesQuery({ title: 'Morning loop' }, 'tempo'), false);
});

test('a run with no name, or a name that is not text, never matches a search', () => {
	assert.equal(runMatchesQuery(null, 'loop'), false);
	assert.equal(runMatchesQuery({}, 'loop'), false);
	assert.equal(runMatchesQuery({ title: 42 }, '42'), false);
});
