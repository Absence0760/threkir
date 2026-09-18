import { expect, test } from '../fixtures/mock-route';

/**
 * /login — a sign-up that returns no session (email confirmation
 * pending) must show the check-your-email notice AND drop back to the
 * sign-in form. Leaving the filled-in sign-up form mounted under the
 * banner reads as "nothing happened", which is what a real signup on
 * prod looked like.
 *
 * Local Supabase runs with enable_confirmations = false
 * (apps/backend/supabase/config.toml), so a real GoTrue always returns
 * a session here — both tests intercept /auth/v1/signup and return the
 * shapes production sends. The two shapes must produce an IDENTICAL
 * outcome: a fresh sign-up and a duplicate address that differ in any
 * observable way turn sign-up into an account-existence oracle.
 */

const PASSWORD = 'testtest';

async function acceptCookies(page: import('@playwright/test').Page) {
	// Pre-accept the cookie banner before the module reads localStorage
	// (same reason as the signIn helper) so it can't intercept clicks.
	await page.addInitScript(() => {
		localStorage.setItem(
			'cookie_consent',
			JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
		);
	});
}

async function submitSignUp(page: import('@playwright/test').Page, email: string) {
	await page.goto('/login?signup=1');
	await expect(page.getByRole('heading', { name: 'Create an account' })).toBeVisible({
		timeout: 5_000
	});

	const submit = page.getByRole('button', { name: 'Sign Up' });
	await page.getByPlaceholder('Email address').fill(email);
	// exact: true — a bare 'Password' also substring-matches the
	// sign-up-only 'Confirm password' field.
	await page.getByPlaceholder('Password', { exact: true }).fill(PASSWORD);
	await page.getByPlaceholder('Confirm password').fill(PASSWORD);
	await page.getByLabel(/I confirm I am 16 years of age or older/).check();
	await page.getByLabel(/I have read and agree to the/).check();
	await expect(submit).toBeEnabled();
	await submit.click();
}

async function expectConfirmationPendingState(
	page: import('@playwright/test').Page,
	email: string
) {
	// The notice names the address the link went to.
	const info = page.locator('.info');
	await expect(info).toBeVisible({ timeout: 5_000 });
	await expect(info).toContainText(email);

	// Back on the sign-in form: the sign-up-only fields and consent
	// boxes are gone, so the page no longer reads as "nothing happened".
	await expect(page.getByRole('heading', { name: 'Create an account' })).toBeHidden();
	await expect(page.getByPlaceholder('Confirm password')).toHaveCount(0);
	await expect(page.getByLabel(/I confirm I am 16 years of age or older/)).toHaveCount(0);
	await expect(page.getByRole('button', { name: 'Sign In' })).toBeVisible();

	// The password is cleared but the address is kept — this user's next
	// act, after the mail, is signing in with it.
	await expect(page.getByPlaceholder('Password', { exact: true })).toHaveValue('');
	await expect(page.getByPlaceholder('Email address')).toHaveValue(email);

	// ?signup=1 is dropped, so a refresh doesn't restore the form.
	await expect(page).toHaveURL(/\/login(?!.*signup=1)/);
}

test.describe('/login sign-up with confirmation pending', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('fresh sign-up: notice shown and the form drops back to sign-in', async ({ page, mockRoute }) => {
		const email = 'e2e-pending@test.local';
		await acceptCookies(page);

		// GoTrue's confirmation-pending shape: the user row, flat, with
		// no access_token — auth-js resolves that to session: null.
		await mockRoute(page, '**/auth/v1/signup*', async (route) => {
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					id: '00000000-0000-0000-0000-0000000000aa',
					aud: 'authenticated',
					role: '',
					email,
					confirmation_sent_at: new Date().toISOString(),
					created_at: new Date().toISOString(),
					updated_at: new Date().toISOString(),
					app_metadata: { provider: 'email', providers: ['email'] },
					user_metadata: {},
					identities: []
				})
			});
		});

		await submitSignUp(page, email);
		await expectConfirmationPendingState(page, email);
	});

	test('already-registered address collapses to the identical state', async ({ page }) => {
		const email = 'e2e-existing@test.local';
		await acceptCookies(page);

		// With confirmations OFF, GoTrue names the duplicate outright.
		// The call site collapses it so the two outcomes stay
		// indistinguishable regardless of the dashboard toggle.
		await page.route('**/auth/v1/signup*', async (route) => {
			await route.fulfill({
				status: 422,
				contentType: 'application/json',
				body: JSON.stringify({
					code: 'user_already_exists',
					error_code: 'user_already_exists',
					msg: 'User already registered'
				})
			});
		});

		await submitSignUp(page, email);
		await expectConfirmationPendingState(page, email);
		// No trace of the distinct "that email already has an account"
		// copy anywhere on the page.
		await expect(page.locator('.error[role="alert"]')).toHaveCount(0);
	});
});
