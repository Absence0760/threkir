import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /social title row: each tab's one primary action sits on the PageHeader's
 * title row, the web analogue of mobile's per-tab FAB. Clubs carries Create
 * club, Challenges carries Create challenge, and Feed carries neither.
 */
test.describe('/social — title-row primary action per tab', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const created: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of created) {
			await admin.from('challenges').delete().eq('id', id);
		}
		created.length = 0;
	});

	test('Create challenge on the Challenges title row creates a challenge and opens it', async ({
		page
	}) => {
		const title = `e2e-social-challenge ${Date.now()}`;

		await page.goto('/social?tab=challenges');
		const header = page.getByTestId('page-header');
		await expect(header.getByRole('heading', { level: 1, name: 'Social' })).toBeVisible({
			timeout: 10_000
		});

		await header.getByRole('button', { name: /Create challenge/ }).click();
		const modal = page.locator('.modal', { hasText: /Create challenge/ });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		await modal.getByLabel(/Title/).fill(title);
		await modal.getByLabel(/Goal/).fill('100');
		await modal.getByRole('button', { name: /Create challenge/ }).click();

		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});
		await expect(page).toHaveURL(/\/challenges\/[^/?#]+$/);
		created.push(new URL(page.url()).pathname.split('/').pop()!);
	});

	test('Feed has no title-row action; Create club shows only on Clubs', async ({ page }) => {
		await page.goto('/social');
		const header = page.getByTestId('page-header');
		await expect(header.getByRole('heading', { level: 1, name: 'Social' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByRole('tab', { name: /Feed/ })).toHaveAttribute('aria-selected', 'true');
		await expect(header.getByRole('button')).toHaveCount(0);

		await page.getByRole('tab', { name: /Clubs/ }).click();
		await expect(page).toHaveURL(/\/social\?tab=clubs/, { timeout: 5_000 });
		await expect(header.getByRole('button', { name: /Create club/ })).toBeVisible();
		await expect(header.getByRole('button', { name: /Create challenge/ })).toHaveCount(0);

		await page.getByRole('tab', { name: /Challenges/ }).click();
		await expect(page).toHaveURL(/\/social\?tab=challenges/, { timeout: 5_000 });
		await expect(header.getByRole('button', { name: /Create challenge/ })).toBeVisible();
		await expect(header.getByRole('button', { name: /Create club/ })).toHaveCount(0);

		await page.getByRole('tab', { name: /People/ }).click();
		await expect(page).toHaveURL(/\/social\?tab=people/, { timeout: 5_000 });
		await expect(header.getByRole('button')).toHaveCount(0);
	});
});
