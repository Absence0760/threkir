import type { Browser, Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { noonOnBrowserDay } from '../fixtures/dates';
import { acceptCookieConsent } from '../fixtures/helpers';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun, setUserSetting } from '../fixtures/simulate';

/**
 * /dashboard is Today and /dashboard/progress is Progress (issue #1374,
 * decisions § 2492; the web twin of mobile's Today and Progress). Today holds
 * what to do now and what was just done: the hero, the last run, a goals
 * strip, one progress summary card and the Coach row. The week lead, the
 * totals, the full goals and the trend groups are one click away on
 * Progress, and the summary card and goals strip are that click.
 */

async function open(browser: Browser, user: SagaUser, path: string): Promise<{ page: Page; close: () => Promise<void> }> {
	const ctx = await browser.newContext({ storageState: user.storageStatePath, viewport: { width: 390, height: 844 } });
	await acceptCookieConsent(ctx);
	const page = await ctx.newPage();
	await page.goto(path);
	return { page, close: () => ctx.close() };
}

test.describe('/dashboard Today and /dashboard/progress', () => {
	let runner: SagaUser;

	test.beforeAll(async () => {
		[runner] = await createSagaUsers(1, { displayNames: ['Today Progress Runner'] });
		for (const d of [2, 4, 6, 9]) {
			await insertRun({ user_id: runner.id, started_at: noonOnBrowserDay(-d), distance_m: 6000, duration_s: 2100 });
		}
		// The weekly distance goal shows as a goal on both pages.
		await setUserSetting(runner.id, 'weekly_mileage_goal_m', 30_000);
	});

	test.afterAll(async () => {
		if (runner) await deleteSagaUsers([runner]);
	});

	test('Today is short, and the trends are not on it', async ({ browser }) => {
		const { page, close } = await open(browser, runner, '/dashboard');
		try {
			await expect(page.getByRole('heading', { level: 1, name: 'Today' })).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('dash-today-hero')).toBeVisible();
			await expect(page.getByTestId('today-last-run')).toBeVisible();
			await expect(page.getByTestId('today-goals-strip')).toContainText('%');
			const summary = page.getByTestId('today-progress-summary');
			await expect(summary).toBeVisible();
			await expect(summary).toContainText('This week');
			await expect(summary).toContainText('This month');

			// The week lead, the totals and the trend groups moved to Progress.
			await expect(page.getByTestId('dash-week-lead')).toHaveCount(0);
			await expect(page.getByTestId('dash-total-runs')).toHaveCount(0);
			await expect(page.locator('section.trend-group')).toHaveCount(0);
		} finally {
			await close();
		}
	});

	test('the summary card opens Progress, which holds the trends and leads back to Today', async ({ browser }) => {
		const { page, close } = await open(browser, runner, '/dashboard');
		try {
			await page.getByTestId('today-progress-summary').click({ timeout: 15_000 });
			await page.waitForURL(/\/dashboard\/progress$/, { timeout: 10_000 });
			await expect(page.getByRole('heading', { level: 1, name: 'Progress' })).toBeVisible();
			await expect(page.getByTestId('dash-week-lead')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('dash-total-runs')).toHaveText('4');
			await expect(page.locator('section.trend-group').first()).toBeVisible();
			await expect(page.getByTestId('dash-today-hero')).toHaveCount(0);

			await page.getByRole('link', { name: 'Today' }).first().click();
			await page.waitForURL(/\/dashboard$/, { timeout: 10_000 });
		} finally {
			await close();
		}
	});

	test('the goals strip opens the full goals on Progress', async ({ browser }) => {
		const { page, close } = await open(browser, runner, '/dashboard');
		try {
			await page.getByTestId('today-goals-strip').click({ timeout: 15_000 });
			await page.waitForURL(/\/dashboard\/progress#goals$/, { timeout: 10_000 });
			await expect(page.locator('#goals .goal-card').first()).toBeVisible({ timeout: 15_000 });
		} finally {
			await close();
		}
	});
});
