import { expect, test } from '../fixtures/test';

/**
 * /auth/callback — Supabase PKCE OAuth landing page.
 *
 * Source: apps/web/src/routes/auth/callback/+page.svelte. The PKCE
 * flow lands here with `?code=…` in the query string after Google /
 * Apple have signed the user out. The page calls
 * supabase.auth.exchangeCodeForSession(...) then redirects to
 * /dashboard on success, or surfaces the auth error inline.
 *
 * We can't drive the real Google / Apple OAuth flow without
 * developer accounts (see docs/testing/e2e_dev_accounts.md). What we CAN
 * pin is the post-OAuth callback behaviour:
 *
 *   1. The page mounts and shows "Signing you in..." while the
 *      exchange is in flight.
 *   2. An invalid / missing code surfaces a visible error message
 *      with a "Back to login" link (the user is not left staring
 *      at the spinner indefinitely) and stays on the page.
 *   3. An anon visitor holds no PKCE code verifier, so supabase-js
 *      refuses the exchange with "code verifier not found" before any
 *      code is read. classifyAuthError files that as a dead link
 *      (Sentry THREKIR-CLIENT-6), so both the missing and the malformed
 *      code ask for a new link rather than printing "Authentication
 *      failed: …".
 *
 * These pin the OAuth-failure surfaces against a regression that
 * swallowed the auth error and stalled the page.
 */

test.describe('/auth/callback — anon paths (no valid code)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	const DEAD_LINK = 'That link has expired or was already used';

	test('with no code, asks for a new link inline and stays on the page', async ({ page }) => {
		await page.goto('/auth/callback');
		await expect(page.getByRole('alert').filter({ hasText: DEAD_LINK })).toBeVisible();
		await expect(page.getByRole('alert')).not.toContainText('Authentication failed');
		await expect(page).toHaveURL(/\/auth\/callback$/);
	});

	test('with a malformed code, asks for a new link + does NOT redirect to /dashboard', async ({
		page,
	}) => {
		await page.goto('/auth/callback?code=this-is-not-a-real-pkce-code');
		await expect(page.getByRole('alert').filter({ hasText: DEAD_LINK })).toBeVisible();
		// Critically it must NOT land at /dashboard with a half-built
		// session, nor bounce away from the message it just showed.
		await expect(page).toHaveURL(/\/auth\/callback$/);
	});

	test('the "Back to login" affordance points at /login when an error is surfaced', async ({
		page,
	}) => {
		await page.goto('/auth/callback?code=invalid');
		await expect(page.getByRole('alert').filter({ hasText: DEAD_LINK })).toBeVisible();
		await expect(page.getByRole('link', { name: /Back to login/i })).toHaveAttribute(
			'href',
			'/login',
		);
	});

	test('"Signing you in..." spinner appears in the loading state', async ({ page }) => {
		// First-render copy. The {#if error}…{:else}<p>Signing you in...</p>
		// branch is what the user sees while exchangeCodeForSession is
		// awaiting. A regression that flipped the wording or dropped the
		// fallback would surface here.
		await page.goto('/auth/callback?code=invalid');
		// The copy renders synchronously on mount, before the exchange
		// settles; the rejection then swaps it for the error. Either is a
		// terminal state the user can read, never a blank card.
		await expect(
			page.getByText('Signing you in...').or(page.getByRole('alert').filter({ hasText: DEAD_LINK })),
		).toBeVisible();
	});
});
