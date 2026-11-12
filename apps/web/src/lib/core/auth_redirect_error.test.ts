import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	authRedirectError,
	authRedirectErrorDetail,
	decodeLinkRefusal,
	encodeLinkRefusal,
	parseLinkProvider,
} from './auth_redirect_error.js';
import { linkRefusalMessageKey } from './link_refusal_message.js';

// --- authRedirectError --------------------------------------------------

test('a refusal in the query is read', () => {
	assert.deepEqual(
		authRedirectError(
			'?error=server_error&error_code=identity_already_exists&error_description=Identity+is+already+linked+to+another+user',
			'',
		),
		{
			error: 'server_error',
			code: 'identity_already_exists',
			description: 'Identity is already linked to another user',
		},
	);
});

test('a refusal in the fragment is read', () => {
	assert.deepEqual(
		authRedirectError('', '#error=access_denied&error_code=bad_oauth_state&error_description=OAuth%20state%20expired'),
		{ error: 'access_denied', code: 'bad_oauth_state', description: 'OAuth state expired' },
	);
});

test('with both, the query wins per key and the fragment fills the rest', () => {
	assert.deepEqual(
		authRedirectError('?error_code=identity_already_exists', '#error=server_error&error_code=other'),
		{ error: 'server_error', code: 'identity_already_exists', description: null },
	);
});

test('no error parameters, no refusal', () => {
	assert.equal(authRedirectError('', ''), null);
	assert.equal(authRedirectError('?code=abc123', ''), null);
	assert.equal(authRedirectError('', '#access_token=t&type=bearer'), null);
	assert.equal(authRedirectError('', '#sign-in-methods'), null);
});

test('an empty value counts as absent', () => {
	assert.equal(authRedirectError('?error=&error_code=&error_description=', ''), null);
});

test('a percent- and plus-encoded description is decoded', () => {
	assert.equal(
		authRedirectError('?error_description=Can%27t+link%3A+50%25%20done', '')?.description,
		"Can't link: 50% done",
	);
});

test('a description alone is still a refusal', () => {
	assert.deepEqual(authRedirectError('?error_description=Nope', ''), {
		error: null,
		code: null,
		description: 'Nope',
	});
});

// --- detail + message key -----------------------------------------------

test('the generic detail prefers the description, then the code, then the error', () => {
	assert.equal(authRedirectErrorDetail({ error: 'e', code: 'c', description: 'd' }), 'd');
	assert.equal(authRedirectErrorDetail({ error: 'e', code: 'c', description: null }), 'c');
	assert.equal(authRedirectErrorDetail({ error: 'e', code: null, description: null }), 'e');
	assert.equal(authRedirectErrorDetail({ error: null, code: null, description: null }), 'unspecified_error');
});

test('each identity-link code GoTrue sends gets its own message', () => {
	assert.equal(linkRefusalMessageKey('identity_already_exists'), 'settingsAccount.linkIdentityTaken');
	assert.equal(linkRefusalMessageKey('identity_not_found'), 'settingsAccount.linkIdentityNotFound');
	assert.equal(linkRefusalMessageKey('single_identity_not_deletable'), 'settingsAccount.needOneMethod');
	assert.equal(linkRefusalMessageKey('manual_linking_disabled'), 'settingsAccount.linkingDisabled');
});

test('any other code, or none, falls back to the generic link failure', () => {
	assert.equal(linkRefusalMessageKey('bad_oauth_state'), 'settingsAccount.linkFailed');
	assert.equal(linkRefusalMessageKey(null), 'settingsAccount.linkFailed');
});

// --- link marker + hand-off ---------------------------------------------

test('only a linkable provider is accepted as a link marker', () => {
	assert.equal(parseLinkProvider('google'), 'google');
	assert.equal(parseLinkProvider('apple'), 'apple');
	assert.equal(parseLinkProvider('github'), null);
	assert.equal(parseLinkProvider(''), null);
	assert.equal(parseLinkProvider(null), null);
});

test('a refusal survives the hand-off to the account page', () => {
	const refusal = {
		provider: 'apple' as const,
		error: 'server_error',
		code: 'identity_already_exists',
		description: 'Identity is already linked to another user',
	};
	assert.deepEqual(decodeLinkRefusal(encodeLinkRefusal(refusal)), refusal);
});

test('a malformed hand-off reads as no refusal', () => {
	assert.equal(decodeLinkRefusal(null), null);
	assert.equal(decodeLinkRefusal(''), null);
	assert.equal(decodeLinkRefusal('{not json'), null);
	assert.equal(decodeLinkRefusal('"google"'), null);
	assert.equal(decodeLinkRefusal(JSON.stringify({ provider: 'github', code: 'x' })), null);
	assert.deepEqual(decodeLinkRefusal(JSON.stringify({ provider: 'google', code: 7 })), {
		provider: 'google',
		error: null,
		code: null,
		description: null,
	});
});
