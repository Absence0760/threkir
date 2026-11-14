import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * New plan and Season plan ask before discarding typed input, and refuse to
 * be left while their create is on the wire (issue #1374 NS-6 / NS-7, the web
 * twin of mobile's EditorPage guard, decisions § 2500). The create is held
 * open by a route that never answers, so no plan is ever written.
 */
test.describe('plan creation unsaved-changes guard', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a dirty New plan form asks before leaving, and Cancel keeps the input', async ({ page }) => {
		await page.goto('/plans/new?type=training');
		const name = page.getByLabel('Plan name');
		await name.waitFor({ timeout: 15_000 });
		await name.fill('e2e guard plan');

		await page.getByRole('link', { name: /Back to plans/ }).click();
		const dialog = page.getByTestId('unsaved-changes-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(page).toHaveURL(/\/plans\/new/);
		await expect(name).toHaveValue('e2e guard plan');

		await page.getByRole('link', { name: /Back to plans/ }).click();
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByRole('button', { name: 'Discard' }).click();
		await page.waitForURL(/\/plans$/, { timeout: 10_000 });
	});

	test('a create in flight cannot be left', async ({ page, mockRoute }) => {
		// Held open: the create never answers, so nothing is written.
		await mockRoute(page, '**/rest/v1/rpc/create_training_plan', () => new Promise(() => {}));
		await page.goto('/plans/new?type=training');
		const name = page.getByLabel('Plan name');
		await name.waitFor({ timeout: 15_000 });
		await name.fill('e2e busy plan');
		await page.getByRole('button', { name: 'Create plan' }).click();
		await expect(page.getByRole('button', { name: /Creating/ })).toBeVisible({ timeout: 10_000 });

		await page.getByRole('link', { name: /Back to plans/ }).click();
		await expect(page.getByTestId('toast-live-polite')).toContainText('Still saving', { timeout: 5_000 });
		await expect(page.getByTestId('unsaved-changes-dialog')).toHaveCount(0);
		await expect(page).toHaveURL(/\/plans\/new/);
	});

	test('a Season plan with a race typed asks before leaving', async ({ page }) => {
		await page.goto('/plans/season');
		await page.getByRole('button', { name: 'Add a race' }).click({ timeout: 15_000 });
		await page.getByTestId('season-race').first().getByLabel('Name').fill('e2e guard race');

		await page.getByRole('link', { name: /Back to new plan/ }).click();
		const dialog = page.getByTestId('unsaved-changes-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByRole('button', { name: 'Discard' }).click();
		await page.waitForURL(/\/plans\/new/, { timeout: 10_000 });
	});

	test('a clean Season plan leaves without asking', async ({ page }) => {
		await page.goto('/plans/season');
		await page.getByRole('button', { name: 'Add a race' }).waitFor({ timeout: 15_000 });
		await page.getByRole('link', { name: /Back to new plan/ }).click();
		await page.waitForURL(/\/plans\/new/, { timeout: 10_000 });
		await expect(page.getByTestId('unsaved-changes-dialog')).toHaveCount(0);
	});
});
