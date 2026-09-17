import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] — publishing is an author action, not a reader action (#902 §3).
 * Both publish rows used to sit between today's session and the plan itself, so
 * every runner scrolled past them to reach this week. They now live in a
 * "Share & publish" section after the week-by-week plan. Pinned on DOM order
 * rather than pixels, so re-hoisting either row above the plan fails here at
 * any viewport.
 */

const RICHMOND_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

test.describe('/plans/[id] publish placement', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('both publish rows sit in a Share & publish section after the plan', async ({ page }) => {
		await page.goto(`/plans/${RICHMOND_HALF_PLAN_ID}`);

		const section = page.getByRole('region', { name: 'Share & publish' });
		await expect(
			section.locator('.publish-row').filter({ has: page.getByLabel('Club to publish to') })
		).toBeVisible({ timeout: 10_000 });
		await expect(
			section.locator('.publish-row').filter({ hasText: 'Public plan library' })
		).toBeVisible();
		await expect(page.locator('.publish-row')).toHaveCount(2);

		const followsPlan = await page.evaluate(() => {
			const weeks = document.querySelector('.weeks');
			if (!weeks) return null;
			return [...document.querySelectorAll('.publish-row')].map(
				(row) => (weeks.compareDocumentPosition(row) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0
			);
		});
		expect(followsPlan).toEqual([true, true]);
	});
});
