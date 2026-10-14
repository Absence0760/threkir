import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	AUDIENCE_LEVELS,
	audienceColumns,
	audienceOf,
	levelRevokesGrants,
	privacyDefaultToAudience,
} from './run_visibility';

test('privacyDefaultToAudience — "public" writes a public row', () => {
	assert.deepEqual(privacyDefaultToAudience('public'), { is_public: true, followers_only: false });
});

test('privacyDefaultToAudience — "followers" writes followers_only, not owner-only', () => {
	assert.deepEqual(privacyDefaultToAudience('followers'), { is_public: false, followers_only: true });
});

test('privacyDefaultToAudience — "private" stays owner-only', () => {
	assert.deepEqual(privacyDefaultToAudience('private'), { is_public: false, followers_only: false });
});

test('privacyDefaultToAudience — missing / unknown pref is fail-closed (owner-only)', () => {
	for (const pref of [null, undefined, '', 'everyone', 'PUBLIC']) {
		assert.deepEqual(privacyDefaultToAudience(pref), { is_public: false, followers_only: false });
	}
});

test('audienceColumns — specific people is a private row; grants carry the audience', () => {
	assert.deepEqual(audienceColumns('specific'), { is_public: false, followers_only: false });
	assert.deepEqual(audienceColumns('private'), audienceColumns('specific'));
});

test('audienceColumns never sets both columns', () => {
	for (const level of AUDIENCE_LEVELS) {
		const c = audienceColumns(level);
		assert.ok(!(c.is_public && c.followers_only), level);
	}
});

test('audienceOf — is_public wins over followers_only and grants', () => {
	assert.equal(audienceOf({ is_public: true, followers_only: true }, 3), 'public');
});

test('audienceOf — followers_only reads as followers whatever the grants', () => {
	assert.equal(audienceOf({ is_public: false, followers_only: true }, 0), 'followers');
	assert.equal(audienceOf({ is_public: false, followers_only: true }, 2), 'followers');
});

test('audienceOf — a private row is specific people exactly when a grant is live', () => {
	assert.equal(audienceOf({ is_public: false, followers_only: false }, 1), 'specific');
	assert.equal(audienceOf({ is_public: false, followers_only: false }, 0), 'private');
	assert.equal(audienceOf({ is_public: null }, 0), 'private');
});

test('audienceOf round-trips every level through audienceColumns', () => {
	for (const level of AUDIENCE_LEVELS) {
		assert.equal(audienceOf(audienceColumns(level), level === 'specific' ? 1 : 0), level);
	}
});

test('levelRevokesGrants — only "only me" revokes', () => {
	assert.deepEqual(
		AUDIENCE_LEVELS.filter(levelRevokesGrants),
		['private'],
	);
});
