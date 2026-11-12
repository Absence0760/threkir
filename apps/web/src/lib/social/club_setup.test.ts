import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { TEXT_LIMITS } from '../core/text_limits.ts';
import { guide as createAClubGuide } from '../help/guides/create-a-club.ts';
import { CREATE_CLUB_GUIDE_ID, clubSetupHref, prefilledClubName } from './club_setup.ts';

test('the help link names the create-a-club guide that ships', () => {
	assert.equal(createAClubGuide.id, CREATE_CLUB_GUIDE_ID);
});

test('a searched name rides to the create form, encoded', () => {
	assert.equal(clubSetupHref('Riverside Harriers & AC'), '/clubs/new?name=Riverside%20Harriers%20%26%20AC');
});

test('a blank or missing query links to the bare create form', () => {
	assert.equal(clubSetupHref('   '), '/clubs/new');
	assert.equal(clubSetupHref(null), '/clubs/new');
	assert.equal(clubSetupHref(undefined), '/clubs/new');
});

test('the prefill is trimmed and capped at the club-name limit in code points', () => {
	assert.equal(prefilledClubName('  Lakeside Joggers  '), 'Lakeside Joggers');
	const long = 'a'.repeat(TEXT_LIMITS.clubName + 20);
	assert.equal(prefilledClubName(long).length, TEXT_LIMITS.clubName);
	const astral = '\u{20000}'.repeat(TEXT_LIMITS.clubName + 5);
	assert.equal(Array.from(prefilledClubName(astral)).length, TEXT_LIMITS.clubName);
});

test('a name that only becomes trailing space at the cap is trimmed again', () => {
	const name = `${'b'.repeat(TEXT_LIMITS.clubName - 1)} tail`;
	assert.equal(prefilledClubName(name), 'b'.repeat(TEXT_LIMITS.clubName - 1));
});
