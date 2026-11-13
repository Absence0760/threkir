import { expect, test } from '../fixtures/test';

import { USER_A, USER_B } from '../fixtures/users';

/**
 * New message from the inbox (issue #1374, decisions § 2493): the picker
 * lists the viewer's follow graph in both directions, each person labelled
 * with how you are connected, and a pick opens the conversation. USER_A and
 * USER_B follow each other in the seed. Nothing is sent, so nothing to clean.
 */
test.describe('/messages — New message', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('lists a followed runner with the relationship and opens the thread', async ({ page }) => {
		await page.goto('/messages');
		await page.getByTestId('inbox-new-message').click({ timeout: 15_000 });
		const dialog = page.getByTestId('new-message-dialog');
		await expect(dialog).toBeVisible();

		const alex = dialog.getByTestId('new-message-person').filter({ hasText: 'Alex Chen' });
		await expect(alex).toBeVisible({ timeout: 10_000 });
		await expect(alex).toContainText('You follow each other');

		await dialog.getByLabel('Search people').fill('zzz-nobody');
		await expect(dialog.getByText('No one matches that name.')).toBeVisible();
		await dialog.getByLabel('Search people').fill('alex');
		await alex.click();

		await page.waitForURL(new RegExp(`/messages/${USER_B.id}$`), { timeout: 10_000 });
		await expect(dialog).toHaveCount(0);
		await expect(page.getByPlaceholder('Message…')).toBeVisible({ timeout: 10_000 });
	});

	test('a failed people read says so and retries, not "nobody to message"', async ({ page, mockRoute }) => {
		let failedOnce = false;
		await mockRoute(page, '**/rest/v1/user_follows*', async (route) => {
			if (!failedOnce) {
				failedOnce = true;
				await route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' });
			} else {
				await route.continue();
			}
		});
		await page.goto('/messages');
		await page.getByTestId('inbox-new-message').click({ timeout: 15_000 });
		const dialog = page.getByTestId('new-message-dialog');
		await expect(dialog.getByTestId('new-message-load-error')).toBeVisible({ timeout: 10_000 });
		await expect(dialog.getByTestId('new-message-empty')).toHaveCount(0);

		await dialog.getByRole('button', { name: 'Retry' }).click();
		await expect(dialog.getByTestId('new-message-person').first()).toBeVisible({ timeout: 10_000 });
	});
});
