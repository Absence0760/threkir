import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { clubLogoSrc } from './club_logo.ts';

const LOCAL = 'http://127.0.0.1:24321';
const LOGO = `${LOCAL}/storage/v1/object/public/avatars/clubs/11111111-1111-1111-1111-111111111111/logo.jpg?v=1`;

test('an https logo passes whatever the origin', () => {
	const url = 'https://cdn.example.com/avatars/clubs/x/logo.jpg';
	assert.equal(clubLogoSrc(url, LOCAL), url);
	assert.equal(clubLogoSrc(url, null), url);
});

test('an http logo on the configured origin club path passes', () => {
	assert.equal(clubLogoSrc(LOGO, LOCAL), LOGO);
	assert.equal(clubLogoSrc(LOGO, `${LOCAL}/`), LOGO);
});

test('an http URL off the club-logo path is refused', () => {
	assert.equal(clubLogoSrc(`${LOCAL}/storage/v1/object/public/avatars/u1/avatar.jpg`, LOCAL), '');
	assert.equal(clubLogoSrc('http://evil.example/storage/v1/object/public/avatars/clubs/x/logo.jpg', LOCAL), '');
});

test('a look-alike host that only shares the prefix is refused', () => {
	assert.equal(
		clubLogoSrc('http://127.0.0.1:24321.evil.example/storage/v1/object/public/avatars/clubs/x/logo.jpg', LOCAL),
		'',
	);
});

test('a hostile scheme or a malformed origin is refused', () => {
	assert.equal(clubLogoSrc('javascript:alert(1)', LOCAL), '');
	assert.equal(clubLogoSrc(LOGO, 'javascript:'), '');
	assert.equal(clubLogoSrc(LOGO, `${LOCAL}/path`), '');
});

test('no url, or no origin for an http url, falls back to the initial', () => {
	assert.equal(clubLogoSrc(null, LOCAL), '');
	assert.equal(clubLogoSrc('', LOCAL), '');
	assert.equal(clubLogoSrc(LOGO, null), '');
});
