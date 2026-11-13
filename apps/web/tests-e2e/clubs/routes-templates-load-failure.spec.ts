import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug] Routes and Templates tabs — a failed read is an error with
 * Retry, never the "no club routes yet" / "no templates" empty state (issue
 * #1374 FS-3). The readers used to log the PostgREST error and return [], so
 * an offline member was told the club had shared nothing.
 */

async function failFirst(page: Page, table: string, marker: string) {
	let fail = true;
	await page.route(`**/rest/v1/${table}*`, async (route) => {
		const req = route.request();
		if (req.method() !== 'GET' || !req.url().includes(marker) || !fail) {
			await route.continue();
			return;
		}
		fail = false;
		await route.fulfill({
			status: 500,
			contentType: 'application/json',
			body: JSON.stringify({ message: `simulated ${table} failure` })
		});
	});
}

test.describe('/clubs/[slug] — Routes and Templates on a failed read', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('Routes shows the error with Retry, and Retry loads the tab', async ({ page }) => {
		await failFirst(page, 'routes', 'club_id=eq.');
		await page.goto('/clubs/richmond-run-club');
		await page.getByRole('tab', { name: /^Routes/ }).click();

		const error = page.getByTestId('club-routes-error');
		await expect(error).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('No club routes yet')).toHaveCount(0);

		await error.getByRole('button', { name: 'Retry' }).click();
		await expect(error).toHaveCount(0, { timeout: 10_000 });
	});

	test('Templates shows the error with Retry, and Retry loads the tab', async ({ page }) => {
		await failFirst(page, 'training_plans', 'is_template=eq.true');
		await page.goto('/clubs/richmond-run-club');
		await page.getByRole('tab', { name: /^Templates/ }).click();

		const error = page.getByTestId('club-templates-error');
		await expect(error).toBeVisible({ timeout: 10_000 });

		await error.getByRole('button', { name: 'Retry' }).click();
		await expect(error).toHaveCount(0, { timeout: 10_000 });
	});
});
