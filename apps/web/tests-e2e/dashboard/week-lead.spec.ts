import type { Locator } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { noonOnBrowserDay } from '../fixtures/dates';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * /dashboard/progress leads with this week (#905 workstream 3).
 *
 * An account with runs used to open on the plan hero, or the plan promo, and
 * then a source filter and a stat grid — with the only "Add a run" action
 * inside the Recent runs card, below every derived metric on the page. The
 * first screen now opens on this week's distance against the plan, the
 * runner's weekly goal or their recent average, and the plan's next session.
 * Add a run and Import sit one tap away in the page's Add or import menu, not
 * on the lead (decisions § 2281), and the lead is Home's one this-week view:
 * its Week summary opens the weekly summary that now holds the day strip and
 * the week's climb (§ 2283).
 * Nothing below it moved out of existence, so the stat grid and the plan hero
 * are asserted present as well as ordered. Since #1187 the adaptive Today hero
 * leads Today (decisions § 2385); since the Today / Progress split
 * (decisions § 2492) the week lead opens Progress and the Add or import menu
 * sits in Today's header.
 */

async function precedes(a: Locator, b: Locator): Promise<boolean> {
	const other = await b.elementHandle();
	return a.evaluate(
		(el, target) => !!target && !!(el.compareDocumentPosition(target) & Node.DOCUMENT_POSITION_FOLLOWING),
		other,
	);
}

test.describe('/dashboard/progress — this week leads', () => {
	let user: SagaUser;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Week Lead Runner'] });
		for (const [offset, distance_m] of [
			[0, 5_000],
			[-8, 8_000],
			[-15, 6_000],
		] as const) {
			await insertRun({
				user_id: user.id,
				started_at: noonOnBrowserDay(offset),
				distance_m,
				duration_s: Math.round(distance_m * 0.33),
			});
		}
	});

	test.afterAll(async () => {
		if (user) await deleteSagaUsers([user]);
	});

	test('a planless account opens on this week against its recent average, with Add a run one tap away above the fold', async ({
		browser,
	}) => {
		for (const viewport of [
			{ width: 1280, height: 720 },
			{ width: 390, height: 844 },
		]) {
			const ctx = await browser.newContext({ storageState: user.storageStatePath, viewport });
			await acceptCookieConsent(ctx);
			const page = await ctx.newPage();
			try {
				// Add a run lives in Today's header menu, above the fold.
				await page.goto('/dashboard');
				const trigger = page.getByTestId('dash-actions-trigger');
				await expect(trigger).toBeInViewport();
				await expect(trigger).toHaveAttribute('aria-expanded', 'false');
				await trigger.click();
				const menu = page.getByRole('menu');
				const add = menu.getByRole('menuitem', { name: 'Add a run' });
				await expect(add).toHaveAttribute('href', '/runs/new');
				await expect(add).toBeFocused();
				await expect(add).toBeInViewport();
				const importLink = menu.getByRole('menuitem', { name: 'Import from Strava / Garmin' });
				await expect(importLink).toHaveAttribute('href', '/settings/integrations');
				await expect(importLink).toBeInViewport();
				await page.keyboard.press('Escape');
				await expect(menu).toHaveCount(0);
				await expect(trigger).toBeFocused();

				await page.goto('/dashboard/progress');
				const lead = page.getByTestId('dash-week-lead');
				await expect(lead).toBeVisible({ timeout: 15_000 });

				await expect(lead.getByTestId('dash-week-lead-distance')).toContainText(/1 activity/);
				await expect(lead.getByTestId('dash-week-lead-vs')).toContainText(/weekly average over the last \d weeks/i);
				await expect(lead.getByTestId('dash-week-lead-next')).toHaveCount(0);

				// The lead carries no actions of its own any more.
				await expect(lead.getByRole('link')).toHaveCount(0);

				// One this-week view: no Week tile in the grid, no day strip.
				await expect(page.locator('.stat-grid').getByText('This Week', { exact: true })).toHaveCount(0);
				await expect(page.locator('.week-strip')).toHaveCount(0);

				const statGrid = page.locator('.stat-grid');
				await expect(statGrid).toBeVisible();
				expect(await precedes(lead, statGrid)).toBe(true);
				await expect(page.getByTestId('dash-first-run')).toHaveCount(0);
			} finally {
				await ctx.close();
			}
		}
	});

	test('the Add or import menu keeps the menu-button keyboard contract', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');
			const trigger = page.getByTestId('dash-actions-trigger');
			await expect(trigger).toBeVisible({ timeout: 15_000 });
			const menu = page.getByRole('menu');
			const add = menu.getByRole('menuitem', { name: 'Add a run' });
			const importLink = menu.getByRole('menuitem', { name: 'Import from Strava / Garmin' });

			// ArrowDown on the trigger opens on the first item; arrows cycle.
			await trigger.focus();
			await page.keyboard.press('ArrowDown');
			await expect(trigger).toHaveAttribute('aria-expanded', 'true');
			await expect(add).toBeFocused();
			await page.keyboard.press('ArrowDown');
			await expect(importLink).toBeFocused();
			await page.keyboard.press('ArrowDown');
			await expect(add).toBeFocused();
			await page.keyboard.press('ArrowUp');
			await expect(importLink).toBeFocused();
			await page.keyboard.press('Home');
			await expect(add).toBeFocused();
			await page.keyboard.press('End');
			await expect(importLink).toBeFocused();

			// Escape closes back to the trigger.
			await page.keyboard.press('Escape');
			await expect(menu).toHaveCount(0);
			await expect(trigger).toBeFocused();
			await expect(trigger).toHaveAttribute('aria-expanded', 'false');

			// ArrowUp on the trigger opens on the last item; Tab out closes.
			await page.keyboard.press('ArrowUp');
			await expect(importLink).toBeFocused();
			await page.keyboard.press('Tab');
			await expect(menu).toHaveCount(0);
			await expect(trigger).toHaveAttribute('aria-expanded', 'false');

			// Shift+Tab from the first item goes back to the trigger, closed.
			await trigger.focus();
			await page.keyboard.press('ArrowDown');
			await expect(add).toBeFocused();
			await page.keyboard.press('Shift+Tab');
			await expect(menu).toHaveCount(0);
			await expect(trigger).toBeFocused();

			// A click on the trigger while it is open closes it, rather than
			// the focus leaving the panel closing it and the click reopening it.
			await trigger.click();
			await expect(add).toBeFocused();
			await trigger.click();
			await expect(menu).toHaveCount(0);
			await expect(trigger).toHaveAttribute('aria-expanded', 'false');
			await expect(trigger).toBeFocused();

			// A click outside closes it.
			await trigger.click();
			await expect(menu).toBeVisible();
			await page.getByRole('heading', { level: 1, name: 'Today' }).click({ position: { x: 2, y: 2 } });
			await expect(menu).toHaveCount(0);
			await expect(trigger).toHaveAttribute('aria-expanded', 'false');
		} finally {
			await ctx.close();
		}
	});

	test('a weekly distance goal replaces the recent average as the yardstick', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx, {
			[`run_app.goals_v1:${user.id}`]: JSON.stringify([{ id: 'wk', period: 'week', distance_m: 20_000 }])
		});
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard/progress');
			const lead = page.getByTestId('dash-week-lead');
			await expect(lead).toBeVisible({ timeout: 15_000 });
			await expect(lead.getByTestId('dash-week-lead-vs')).toContainText(/weekly goal/i);
			await expect(lead.getByTestId('dash-week-lead-vs')).not.toContainText(/average/i);
			await expect(lead.getByRole('progressbar')).toHaveAttribute('aria-valuenow', '25');
		} finally {
			await ctx.close();
		}
	});

	test.describe('with an active plan', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('the plan hero leads Today, and the next session sits in the lead on Progress', async ({ page }) => {
			await page.goto('/dashboard');
			await expect(page.getByTestId('dash-actions-trigger')).toBeInViewport({ timeout: 15_000 });

			// The adaptive Today hero comes first (decisions § 2385); on a plan it
			// is the plan hero, above the progress summary.
			const hero = page.locator('.plan-hero');
			await expect(hero).toBeVisible();
			await expect(hero).toHaveAttribute('data-testid', 'dash-today-hero');
			const summary = page.getByTestId('today-progress-summary');
			await expect(summary).toBeVisible();
			expect(await precedes(hero, summary)).toBe(true);
			await expect(page.getByTestId('dash-week-lead')).toHaveCount(0);

			await page.goto('/dashboard/progress');
			const lead = page.getByTestId('dash-week-lead');
			await expect(lead).toBeVisible({ timeout: 15_000 });
			await expect(lead.getByTestId('dash-week-lead-next')).toBeVisible();
		});
	});

	test('the lead opens this week\'s summary, with the day strip and the week\'s climb', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard/progress');
			const lead = page.getByTestId('dash-week-lead');
			await expect(lead).toBeVisible({ timeout: 15_000 });
			await lead.getByTestId('dash-week-lead-open').click();
			const dialog = page.getByRole('dialog');
			await expect(dialog).toBeVisible();
			await expect(dialog.getByRole('button', { name: 'Week', exact: true })).toHaveClass(/active/);
			await expect(dialog.locator('.week-strip')).toBeVisible();
			await expect(dialog.getByTestId('period-summary-climb')).toBeVisible();

			// The strip draws only the week holding today.
			await dialog.getByRole('button', { name: /Previous/ }).click();
			await expect(dialog.locator('.week-strip')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
