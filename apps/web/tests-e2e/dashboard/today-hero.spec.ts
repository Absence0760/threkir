import type { Browser, Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { noonOnBrowserDay } from '../fixtures/dates';
import { acceptCookieConsent } from '../fixtures/helpers';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun, setUserSetting } from '../fixtures/simulate';

/**
 * /dashboard opens on an adaptive Today hero (#1187, decisions § 2385): the
 * plan hero on a plan (plan-up-next / plan-race-countdown cover those
 * states), the first-run block on a new account (dashboard-first-run), else
 * today's run, else readiness with a prompt to add one. Whatever the state,
 * the hero is the first card, above the week lead.
 *
 * Trend groups can be hidden from Home and brought back from Settings
 * (`dashboard_hidden_cards`, decisions § 2386).
 */

async function openDashboard(browser: Browser, user: SagaUser): Promise<{ page: Page; close: () => Promise<void> }> {
	const ctx = await browser.newContext({ storageState: user.storageStatePath, viewport: { width: 390, height: 844 } });
	await acceptCookieConsent(ctx);
	const page = await ctx.newPage();
	await page.goto('/dashboard');
	return { page, close: () => ctx.close() };
}

async function heroLeadsLead(page: Page): Promise<void> {
	const hero = page.getByTestId('dash-today-hero');
	const lead = page.getByTestId('dash-week-lead');
	await expect(lead).toBeVisible({ timeout: 15_000 });
	const heroBox = await hero.boundingBox();
	const leadBox = await lead.boundingBox();
	expect(heroBox!.y, 'the Today hero sits above the week lead').toBeLessThan(leadBox!.y);
}

test.describe('/dashboard — the Today hero', () => {
	let noPlan: SagaUser;
	let ranToday: SagaUser;

	test.beforeAll(async () => {
		[noPlan, ranToday] = await createSagaUsers(2, { displayNames: ['Hero No Plan', 'Hero Ran Today'] });
		for (const d of [1, 3, 5, 7, 9, 11]) {
			await insertRun({ user_id: noPlan.id, started_at: noonOnBrowserDay(-d), distance_m: 8000, duration_s: 2700 });
		}
		await insertRun({ user_id: ranToday.id, started_at: noonOnBrowserDay(-3), distance_m: 6000, duration_s: 2000 });
		await insertRun({ user_id: ranToday.id, started_at: noonOnBrowserDay(0), distance_m: 5000, duration_s: 1650 });
	});

	test.afterAll(async () => {
		const users = [noPlan, ranToday].filter(Boolean);
		if (users.length > 0) await deleteSagaUsers(users);
	});

	test('with no plan and no run today, readiness and Add a run lead the page', async ({ browser }) => {
		const { page, close } = await openDashboard(browser, noPlan);
		try {
			const hero = page.getByTestId('dash-today-hero');
			await expect(hero).toHaveAttribute('data-state', 'no_plan', { timeout: 15_000 });
			await expect(hero.getByRole('heading', { name: 'Nothing planned today' })).toBeVisible();
			await expect(hero.locator('.readiness-card')).toBeVisible();
			await expect(hero.getByTestId('dash-hero-add-run')).toHaveAttribute('href', '/runs/new');
			await heroLeadsLead(page);
			// Readiness moved into the hero, so the trend group holds one load card.
			await expect(page.locator('#dash-trend-fitness-title')).toBeVisible();
			await expect(page.locator('section.trend-group .readiness-card')).toHaveCount(0);
			await expect(page.getByTestId('dash-training-load-card')).toHaveCount(1);
		} finally {
			await close();
		}
	});

	test("a run logged today leads, with readiness in one line", async ({ browser }) => {
		const { page, close } = await openDashboard(browser, ranToday);
		try {
			const hero = page.getByTestId('dash-today-hero');
			await expect(hero).toHaveAttribute('data-state', 'ran_today', { timeout: 15_000 });
			await expect(hero).toHaveAttribute('href', /^\/runs\//);
			await expect(hero).toContainText("Today's run");
			await expect(hero).toContainText('5.00');
			await heroLeadsLead(page);
		} finally {
			await close();
		}
	});

	test('a hidden trend group leaves Home and comes back from Settings', async ({ browser }) => {
		await setUserSetting(noPlan.id, 'dashboard_hidden_cards', []);
		const { page, close } = await openDashboard(browser, noPlan);
		try {
			const volume = page.locator('#dash-trend-volume-title');
			await expect(volume).toBeVisible({ timeout: 15_000 });
			await page.getByRole('button', { name: 'Hide Volume from Home' }).click();
			await expect(volume).toHaveCount(0);
			await expect(page.getByText('Volume is hidden. You can bring it back in Settings.')).toBeVisible();

			// Universal, so it survives a reload rather than living in this tab.
			await page.reload();
			await expect(page.locator('#dash-trend-fitness-title')).toBeVisible({ timeout: 15_000 });
			await expect(volume).toHaveCount(0);

			await page.goto('/settings/display');
			const box = page.getByTestId('home-card-volume');
			await expect(box).not.toBeChecked({ timeout: 15_000 });
			await box.check();
			await expect(box).toBeChecked();
			await page.waitForLoadState('networkidle');

			await page.goto('/dashboard');
			await expect(volume).toBeVisible({ timeout: 15_000 });
		} finally {
			await close();
		}
	});
});
