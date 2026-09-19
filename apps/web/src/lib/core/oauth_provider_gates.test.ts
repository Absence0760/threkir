// Both /login OAuth buttons CREATE an account on first sign-in, so both owe
// the same two things: a fail-closed flag (an unwired provider answers a
// click with an opaque error, which is what the "Soon" pill exists to avoid)
// and the sign-up consent gate (16+ / ToS, stashed for /auth/callback to
// stamp — audit/gdpr 2026-05-25 Critical). Apple was hardcoded to the soon
// notice and had no gate at all, so when it was wired the gate was the easy
// thing to forget. These read the page source because the enabled path has no
// e2e: GoTrue validates `google` and `apple` against the real providers, so
// the mock-OIDC lane stands in as `keycloak` and can never click either one.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const loginPage = readFileSync(
	resolve(dirname(fileURLToPath(import.meta.url)), '../../routes/login/+page.svelte'),
	'utf-8',
);

test('each OAuth button picks its handler off its own fail-closed flag', () => {
	for (const [flag, soonKey] of [
		['googleEnabled', 'login.googleSoon'],
		['appleEnabled', 'login.appleSoon'],
	]) {
		assert.match(
			loginPage,
			new RegExp(`onclick=\\{${flag}\\s*\\n?\\s*\\?`),
			`the ${flag} button must choose its onclick off ${flag} — a hardcoded handler is a provider that cannot be turned on.`,
		);
		assert.match(
			loginPage,
			new RegExp(`showProviderSoon\\('${soonKey}'\\)`),
			`the disabled branch must surface ${soonKey}, not start a redirect.`,
		);
		assert.match(
			loginPage,
			new RegExp(`\\{#if !${flag}\\}`),
			`the "Soon" pill must be conditional on ${flag}, or it outlives the gate.`,
		);
	}
});

test('the OAuth sign-in path runs the sign-up gates before any redirect', () => {
	const fn = loginPage.slice(
		loginPage.indexOf('async function startOAuthSignIn'),
		loginPage.indexOf('function showProviderSoon'),
	);
	assert.ok(fn.length > 0, 'startOAuthSignIn must exist — both providers share it.');
	const gateIdx = fn.indexOf('checkSignUpGates(');
	const redirectIdx = fn.indexOf('auth.signInWith');
	assert.ok(gateIdx >= 0, 'startOAuthSignIn must call checkSignUpGates.');
	assert.ok(
		gateIdx < redirectIdx,
		'the consent gate must run BEFORE the provider redirect — after it, the account already exists.',
	);
	assert.ok(
		fn.indexOf('age_confirmed_at') < redirectIdx && fn.indexOf('terms_accepted_at') < redirectIdx,
		'the consent timestamps must be stashed before the redirect; /auth/callback has no other source for them.',
	);
	for (const provider of ['signInWithGoogle', 'signInWithApple']) {
		assert.ok(
			fn.includes(provider),
			`${provider} must be reached through startOAuthSignIn, not from a second handler that skips the gate.`,
		);
	}
});
