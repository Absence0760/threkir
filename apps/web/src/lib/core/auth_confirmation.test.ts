import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	emailOtpLink,
	strayConfirmationTarget,
	verifyConsentStamped,
} from './auth_confirmation.js';

// --- strayConfirmationTarget -------------------------------------------
//
// The whole point of this predicate is that a misconfigured Supabase
// dashboard (Site URL still the default, or the Redirect-URLs allow-list
// missing /auth/callback) cannot silently drop the Art 8 consent stamp.
// Every case below is a landing that must be routed back to the callback,
// or a route that owns its own code and must NOT be hijacked.

test('PKCE code on the app root → routed to the callback, query preserved', () => {
	assert.equal(
		strayConfirmationTarget('/', '?code=abc123', ''),
		'/auth/callback?code=abc123',
	);
});

test('PKCE code on any other route → routed to the callback', () => {
	assert.equal(
		strayConfirmationTarget('/dashboard', '?code=abc123', ''),
		'/auth/callback?code=abc123',
	);
});

test('extra query params ride along so nothing is lost in the hop', () => {
	assert.equal(
		strayConfirmationTarget('/', '?code=abc123&type=signup', ''),
		'/auth/callback?code=abc123&type=signup',
	);
});

test('implicit-flow access token in the hash is also a confirmation landing', () => {
	assert.equal(
		strayConfirmationTarget('/', '', '#access_token=tok&type=signup'),
		'/auth/callback#access_token=tok&type=signup',
	);
});

test('a trailing slash does not defeat the owner check', () => {
	assert.equal(strayConfirmationTarget('/auth/callback/', '?code=abc123', ''), null);
});

test('/auth/callback owns its own code — no redirect loop', () => {
	assert.equal(strayConfirmationTarget('/auth/callback', '?code=abc123', ''), null);
});

test('/auth/reset owns the recovery code — the reset form must keep it', () => {
	assert.equal(strayConfirmationTarget('/auth/reset', '?code=abc123', ''), null);
	assert.equal(strayConfirmationTarget('/auth/reset', '', '#access_token=tok'), null);
});

test('/settings/integrations owns the Strava OAuth code', () => {
	assert.equal(
		strayConfirmationTarget('/settings/integrations', '?code=str&scope=read&state=s', ''),
		null,
	);
});

test('an ordinary page load is not a landing', () => {
	assert.equal(strayConfirmationTarget('/', '', ''), null);
	assert.equal(strayConfirmationTarget('/dashboard', '?tab=week', '#top'), null);
});

test('a param merely containing "code" is not a code', () => {
	assert.equal(strayConfirmationTarget('/', '?discount_code=abc', ''), null);
});

// --- verifyConsentStamped ---------------------------------------------

test('both stamps present → ok', async () => {
	const outcome = await verifyConsentStamped(async () => ({
		data: { age_confirmed_at: '2026-07-20T00:00:00Z', terms_accepted_at: '2026-07-20T00:00:00Z' },
	}));
	assert.equal(outcome, 'ok');
});

test('either stamp null → needs-consent', async () => {
	assert.equal(
		await verifyConsentStamped(async () => ({
			data: { age_confirmed_at: null, terms_accepted_at: '2026-07-20T00:00:00Z' },
		})),
		'needs-consent',
	);
	assert.equal(
		await verifyConsentStamped(async () => ({
			data: { age_confirmed_at: '2026-07-20T00:00:00Z', terms_accepted_at: null },
		})),
		'needs-consent',
	);
});

test('no profile row → needs-consent', async () => {
	assert.equal(await verifyConsentStamped(async () => ({ data: null })), 'needs-consent');
});

test('a failed read fails CLOSED, never open', async () => {
	assert.equal(
		await verifyConsentStamped(() => {
			throw new Error('network');
		}),
		'needs-consent',
	);
	assert.equal(
		await verifyConsentStamped(async () => {
			throw new Error('rpc rejected');
		}),
		'needs-consent',
	);
});

// --- emailOtpLink -------------------------------------------------------
//
// The device-independent half of email confirmation. A token_hash mints
// a session in whatever browser opened the mail; the PKCE code it
// replaced could only be exchanged where the flow started.

test('token_hash + type is read off the landing URL', () => {
	assert.deepEqual(emailOtpLink('?token_hash=abc&type=signup'), {
		token_hash: 'abc',
		type: 'signup',
	});
});

test('recovery, invite, magiclink and both email-change spellings are all links', () => {
	for (const type of ['recovery', 'invite', 'magiclink', 'email_change', 'email']) {
		assert.deepEqual(emailOtpLink(`?token_hash=h&type=${type}`), { token_hash: 'h', type });
	}
});

test('an unknown type is not a link — verifyOtp would reject it anyway', () => {
	assert.equal(emailOtpLink('?token_hash=abc&type=phone_change'), null);
});

test('either half missing is not a link', () => {
	assert.equal(emailOtpLink('?type=signup'), null);
	assert.equal(emailOtpLink('?token_hash=abc'), null);
	assert.equal(emailOtpLink(''), null);
});

test('an OAuth callback is left to the PKCE exchange', () => {
	assert.equal(emailOtpLink('?code=abc123'), null);
});

test('a token_hash landing on the wrong route is routed to the callback', () => {
	assert.equal(
		strayConfirmationTarget('/', '?token_hash=abc&type=signup', ''),
		'/auth/callback?token_hash=abc&type=signup',
	);
});

test('the reset page owns its own token_hash', () => {
	assert.equal(strayConfirmationTarget('/auth/reset', '?token_hash=abc&type=recovery', ''), null);
});
