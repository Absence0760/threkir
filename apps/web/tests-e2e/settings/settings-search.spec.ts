import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * The settings search (issue #1374, decisions § 2494; web twin of the You
 * tab's search on mobile): a query over every settings page's rows lists
 * each match with the page it is on, and a result lands on the row itself:
 * scrolled into view, focused and briefly highlighted (setting_focus.ts).
 */

const NUTRITION_ROW = '#setting-prefs-showNutrition';

async function pickNutrition(page: Page) {
	const search = page.getByTestId('settings-search');
	await search.waitFor({ timeout: 15_000 });
	await search.fill('nutr');
	const hit = page.getByTestId('settings-search-result').filter({ hasText: 'Show Nutrition' }).first();
	await expect(hit).toBeVisible();
	await hit.click();
	await page.waitForURL(/\/settings\/display#setting-prefs-showNutrition$/, { timeout: 10_000 });
}
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
		await page.waitForURL(/\/settings\/training#setting-prefs-heartRateZonesHeading$/, { timeout: 10_000 });
		// Picking a result clears the search and brings the nav back.
		await expect(page.getByTestId('settings-search-results')).toHaveCount(0);
	});

	test('a result lands on its row: in view, focused and highlighted', async ({ page }) => {
		await page.goto('/settings/account');
		await pickNutrition(page);
		const row = page.locator(NUTRITION_ROW);
		await expect(row).toBeInViewport({ timeout: 10_000 });
		await expect(row).toBeFocused();
		await expect(row).toHaveClass(/setting-flash/);
		// The highlight is brief.
		await expect(row).not.toHaveClass(/setting-flash/, { timeout: 5_000 });
		await expect(page.getByTestId('settings-search-results')).toHaveCount(0);
	});

	test('a result for the page already open still lands on the row', async ({ page }) => {
		await page.goto('/settings/display');
		await pickNutrition(page);
		await expect(page.locator(NUTRITION_ROW)).toBeInViewport({ timeout: 10_000 });
		await expect(page.locator(NUTRITION_ROW)).toBeFocused();
		// Picking the same result again highlights the row again.
		await page.evaluate(() => window.scrollTo(0, 0));
		await pickNutrition(page);
		await expect(page.locator(NUTRITION_ROW)).toBeInViewport({ timeout: 10_000 });
		await expect(page.locator(NUTRITION_ROW)).toHaveClass(/setting-flash/);
	});

	test('under reduced motion the highlight holds still', async ({ page }) => {
		await page.emulateMedia({ reducedMotion: 'reduce' });
		await page.goto('/settings/account');
		await pickNutrition(page);
		const row = page.locator(NUTRITION_ROW);
		await expect(row).toBeInViewport({ timeout: 10_000 });
		await expect(row).toHaveClass(/setting-flash/);
		expect(await row.evaluate((el) => getComputedStyle(el).animationName)).toBe('none');
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
