import { expect, test, type Page } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/account — the profile card is closed until its own read lands.
 *
 * The card edits values read on mount (display name, @handle, DOB, HR, the
 * health-consent tick). Before the gate, a field typed into ahead of that read
 * was overwritten when it resolved: `handle.spec.ts` filled "Bad Name!", the
 * read then set the handle back to its saved empty value, and Save stayed
 * disabled until the test timed out — on main, on a slow runner only. And a
 * failed read left the card editable over blanks, so Save wrote them back.
 *
 * Both tests arm the interception on /settings/preferences and reach the
 * account page by a client-side navigation: the auth store reads
 * get_my_profile during auth.ready(), and a router navigation does not re-run
 * it, so the only read the route sees is the account page's own (the same
 * approach preferences-load-failure.spec.ts takes).
 */

async function openAccountThroughTheNav(page: Page) {
	await page.locator('.settings-nav a[href="/settings/account"]').first().click();
	await expect(page.getByRole('heading', { level: 2, name: 'Profile' })).toBeVisible();
}

test.describe('/settings/account — profile load', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ page }) => {
		await page.goto('/settings/preferences');
		await expect(page.locator('.settings-nav a[href="/settings/account"]').first()).toBeVisible();
	});

	test('nothing in the card can be typed into until the saved profile has arrived', async ({
		page
	}) => {
		let release!: () => void;
		const held = new Promise<void>((resolve) => (release = resolve));
		await page.route('**/rest/v1/rpc/get_my_profile**', async (route) => {
			await held;
			await route.fallback();
		});

		await openAccountThroughTheNav(page);
		const input = page.getByTestId('handle-input');
		await expect(input, 'the handle is closed while its saved value is unknown').toBeDisabled();
		await expect(page.getByRole('button', { name: 'Save Profile' })).toBeDisabled();

		release();
		await expect(input).toBeEnabled();
		await input.fill('Bad Name!');
		await expect(input, 'what was typed is not overwritten by the read').toHaveValue('Bad Name!');
		await expect(page.getByTestId('handle-save')).toBeEnabled();
	});

	test('a failed profile read keeps the card closed and offers a retry', async ({ page }) => {
		await page.route('**/rest/v1/rpc/get_my_profile**', (route) =>
			route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ message: 'simulated profile-read failure' })
			})
		);

		await openAccountThroughTheNav(page);
		const banner = page.getByTestId('profile-load-error');
		await expect(banner).toBeVisible();
		await expect(banner).toHaveAttribute('role', 'alert');
		await expect(page.getByTestId('handle-input')).toBeDisabled();
		await expect(page.getByRole('button', { name: 'Save Profile' })).toBeDisabled();

		await page.unroute('**/rest/v1/rpc/get_my_profile**');
		await page.getByTestId('profile-load-retry').click();
		await expect(banner).toHaveCount(0);
		await expect(page.getByTestId('handle-input')).toBeEnabled();
		await expect(page.getByRole('button', { name: 'Save Profile' })).toBeEnabled();
	});
});
