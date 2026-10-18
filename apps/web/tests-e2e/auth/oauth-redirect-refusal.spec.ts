import { expect, test } from '../fixtures/test';
import { USER_A } from '../fixtures/users';

/**
 * A refused OAuth redirect is said out loud, never swallowed.
 *
 * Linking Google from Settings → Account while that Google identity
 * already belongs to another Threkir account makes GoTrue redirect back
 * to /auth/callback with `error` / `error_code` / `error_description`
 * instead of a `code`. supabase-js keeps the runner's existing session
 * through that, so the callback used to find a session, call it success
 * and navigate on: the refusal was invisible. Signed in on purpose here —
 * the live session is exactly what used to hide it.
 */

const REFUSAL =
	'/auth/callback?error=server_error&error_code=identity_already_exists&error_description=Identity+is+already+linked+to+another+user';

test.describe('Refused OAuth redirect', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a refused link lands back on Sign-in methods with the reason and a way forward', async ({
		page,
	}) => {
		// Only on the callback document: the marker is what linkProvider
		// stashes before it hands off to GoTrue.
		await page.addInitScript(() => {
			if (location.pathname === '/auth/callback') {
				sessionStorage.setItem('oauth_link_provider', 'google');
			}
		});

		await page.goto(REFUSAL);

		await expect(page).toHaveURL(/\/settings\/account#sign-in-methods$/);
		const refusal = page.getByTestId('link-refusal');
		await expect(refusal).toBeVisible();
		await expect(refusal).toContainText(
			'That Google account already signs in to a different Threkir account',
		);
		await expect(refusal).toContainText('Download full backup');
		await expect(refusal).toContainText('Delete Account');
		expect(page.url()).not.toMatch(/error(_code|_description)?=/);
		// Handed over once: a reload does not repeat it.
		expect(await page.evaluate(() => sessionStorage.getItem('oauth_link_refusal'))).toBeNull();
		expect(await page.evaluate(() => sessionStorage.getItem('oauth_link_provider'))).toBeNull();
	});

	test('a refused sign-in shows the error on the callback instead of navigating on', async ({
		page,
	}) => {
		await page.goto(REFUSAL);

		// The error branch returns before any navigation, so seeing it is
		// proof the live session was not taken for a successful sign-in.
		await expect(
			page.getByRole('alert').filter({ hasText: 'Identity is already linked to another user' }),
		).toBeVisible();
		await expect(page).toHaveURL(/\/auth\/callback$/);
		await expect(page.getByRole('link', { name: /back to login/i })).toBeVisible();
	});
});
