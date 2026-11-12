import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * /plans/new's club-template picker on a failed read (#1186 round 2).
 *
 * The picker used to vanish when the template read failed, because the data
 * layer answered an empty list: a club's Adopt link (`?from=<id>`) then
 * landed on a page with no picker and no reason. It now says the templates
 * could not be loaded and offers a retry that brings the picker back.
 */

const TEMPLATE_READ = /\/rest\/v1\/training_plans\?.*is_template=eq\.true/;

test.describe('/plans/new template picker load failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
	});

	test('a failed template read says so, and Retry brings the picker back', async ({ page }) => {
		let failNext = true;
		await page.route(TEMPLATE_READ, async (route) => {
			if (failNext && route.request().method() === 'GET') {
				failNext = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated template read failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto('/plans/new?from=00000000-0000-0000-0000-000000000000');
		const failure = page.getByTestId('template-load-error');
		await expect(failure.getByRole('alert')).toContainText("Couldn't load your clubs' plan templates", {
			timeout: 10_000
		});
		await expect(failure).not.toContainText('simulated');

		await failure.getByRole('button', { name: 'Retry' }).click();
		await expect(page.getByTestId('template-load-error')).toHaveCount(0, { timeout: 10_000 });
		await expect(page.locator('.template-picker select')).toBeVisible({ timeout: 10_000 });
	});
});
