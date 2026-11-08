import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * /plans/[id] — the week-by-week list (issue #1186).
 *
 * The seed slides the Richmond Half plan so today is day 17: week 3 of 12
 * (index 2). Weeks 1 and 2 are behind the runner, so they fold into one
 * summary row and the current week leads the section; the hero's week pill
 * jumps to it.
 */

const PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

test.describe('/plans/[id] — week list', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
	});

	test('earlier weeks fold into one summary row that expands', async ({ page }) => {
		await page.goto(`/plans/${PLAN_ID}`);
		const section = page.locator('section.weeks');
		const summary = section.getByTestId('plan-earlier-weeks');
		await expect(summary).toBeVisible({ timeout: 10_000 });
		await expect(summary).toContainText('2 earlier weeks');
		await expect(summary).toContainText(/\d+\s*\/\s*\d+ done/);
		await expect(summary).toHaveAttribute('aria-expanded', 'false');

		const weekCards = section.getByTestId('plan-week');
		await expect(weekCards).toHaveCount(10);
		await expect(weekCards.first()).toHaveClass(/\bcurrent\b/);
		await expect(weekCards.first().locator('.week-num')).toHaveText('Week 3');
		await expect(weekCards.first().locator('.week-progress')).toContainText(/\d+\s*\/\s*\d+ done/);

		await summary.click();
		await expect(summary).toHaveAttribute('aria-expanded', 'true');
		await expect(weekCards).toHaveCount(12);
		await expect(weekCards.first().locator('.week-num')).toHaveText('Week 1');

		await summary.click();
		await expect(weekCards).toHaveCount(10);
	});

	test('the week pill jumps to the current week', async ({ page }) => {
		await page.setViewportSize({ width: 390, height: 844 });
		await page.goto(`/plans/${PLAN_ID}`);
		const current = page.locator('#plan-week-current');
		await expect(page.getByTestId('week-pill')).toBeVisible({ timeout: 10_000 });
		await expect(current).not.toBeInViewport();

		await page.getByTestId('week-pill').click();
		await expect(current).toBeInViewport();
		await expect(current).toBeFocused();
		await expect(current.locator('.week-num')).toHaveText('Week 3');
	});

	test('the week pill opens a collapsed week list before jumping', async ({ page }) => {
		await page.goto(`/plans/${PLAN_ID}`);
		const summary = page.locator('#plan-weeks-title');
		await expect(page.locator('section.weeks details')).toHaveAttribute('open', '');
		await summary.click();
		await expect(page.locator('section.weeks details')).not.toHaveAttribute('open', '');

		await page.getByTestId('week-pill').click();
		await expect(page.locator('section.weeks details')).toHaveAttribute('open', '');
		await expect(page.locator('#plan-week-current')).toBeInViewport();
	});

	test('an upcoming day draws no box of its own inside the week card', async ({ page }) => {
		await page.goto(`/plans/${PLAN_ID}`);
		const upcoming = page
			.locator('#plan-week-current ~ .week .day[data-status="upcoming"]')
			.first();
		await expect(upcoming).toBeVisible({ timeout: 10_000 });
		const sideColour = await upcoming.evaluate((el) => getComputedStyle(el).borderLeftColor);
		expect(sideColour).toBe('rgba(0, 0, 0, 0)');
	});
});
