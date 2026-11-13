import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * The settings search (issue #1374, decisions § 2494; web twin of the You
 * tab's search on mobile): a query over every settings page's rows lists
 * each match with the page it is on, and a result opens that page.
 */
test.describe('settings search', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('finds a row on another page and opens it', async ({ page }) => {
		await page.goto('/settings/account');
		const search = page.getByTestId('settings-search');
		await search.waitFor({ timeout: 15_000 });
		await search.fill('heart rate zones');

		const hit = page.getByTestId('settings-search-result').filter({ hasText: 'Training' }).first();
		await expect(hit).toBeVisible();
		await hit.click();
		await page.waitForURL(/\/settings\/training/, { timeout: 10_000 });
		// Picking a result clears the search and brings the nav back.
		await expect(page.getByTestId('settings-search-results')).toHaveCount(0);
	});

	test('says so when nothing matches', async ({ page }) => {
		await page.goto('/settings/account');
		const search = page.getByTestId('settings-search');
		await search.waitFor({ timeout: 15_000 });
		await search.fill('zzzz no such setting');
		await expect(page.getByTestId('settings-search-empty')).toContainText('No settings match');
		await expect(page.getByTestId('settings-search-result')).toHaveCount(0);
	});
});
