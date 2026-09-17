import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/body — a failed settings/profile read must FAIL CLOSED
 * (uxhunt-web.md finding #3).
 *
 * The load populates the Art 9 health-consent state + demographics (gender,
 * DOB, height, weight). Previously any load failure only warned to the
 * console and the form rendered its DEFAULTS — so a user could edit and Save,
 * round-tripping defaults back to the server and silently clearing their real
 * values (including the consent-derived fields).
 *
 * The fix: on a failed `get_my_profile` read the page shows a role="alert"
 * banner INSTEAD of the form, which gates every persist path (the auto-save
 * controls and the explicit demographics Save) until a reload succeeds. Since
 * the preferences split (issue #905) that gate lives in the shared
 * `createPrefsPage` + `PrefsPage` shell every preference page renders through,
 * and the body metrics page is the one whose load reads the profile.
 *
 * The auth store reads get_my_profile during auth.ready() — on init AND again
 * on the INITIAL_SESSION onAuthStateChange event — so a fixed ordinal is
 * fragile. Instead: let auth fully settle on a DIFFERENT settings page with
 * reads succeeding, then arm the failure and CLIENT-SIDE navigate — a router
 * navigation doesn't re-run the auth store, so the only get_my_profile that
 * fires is the page's own.
 */
test.describe('/settings/body — load failure fails closed', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed profile read shows a load-error banner and gates every save', async ({
		page,
	}) => {
		let failProfileRead = false;
		await page.route('**/rest/v1/rpc/get_my_profile**', async (route) => {
			if (failProfileRead) {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated profile-read failure' }),
				});
				return;
			}
			await route.fallback();
		});

		await page.goto('/settings/account');
		await expect(page.getByRole('heading', { level: 2, name: 'Profile' })).toBeVisible({
			timeout: 10_000,
		});

		failProfileRead = true;
		await page.locator('.settings-nav a[href="/settings/body"]').first().click();

		const banner = page.getByTestId('prefs-load-error');
		await expect(banner).toBeVisible({ timeout: 10_000 });
		await expect(banner).toHaveAttribute('role', 'alert');

		// Every persist surface is gated: neither the consent-gated Save nor the
		// auto-saving nutrition levers are rendered, so a failed read can't be
		// round-tripped back as defaults.
		await expect(page.getByTestId('save-demographics')).toHaveCount(0);
		await expect(page.getByTestId('activity-level')).toHaveCount(0);

		await page.unroute('**/rest/v1/rpc/get_my_profile**');
		await page.getByTestId('prefs-load-retry').click();
		await expect(banner).toHaveCount(0, { timeout: 10_000 });
		await expect(page.getByTestId('save-demographics')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('activity-level')).toBeVisible();
	});
});
