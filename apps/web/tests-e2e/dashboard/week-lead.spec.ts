import { expect, test, type Locator } from '@playwright/test';

import { noonOnBrowserDay } from '../fixtures/dates';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /dashboard leads with this week (#905 workstream 3).
 *
 * An account with runs used to open on the plan hero, or the plan promo, and
 * then a source filter and a stat grid — with the only "Add a run" action
 * inside the Recent runs card, below every derived metric on the page. The
 * first screen now opens on this week's distance against the plan or the
 * runner's recent average, the plan's next session, and the add action.
 * Nothing below it moved out of existence, so the stat grid and the plan hero
 * are asserted present as well as ordered.
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

async function precedes(a: Locator, b: Locator): Promise<boolean> {
	const other = await b.elementHandle();
	return a.evaluate(
		(el, target) => !!target && !!(el.compareDocumentPosition(target) & Node.DOCUMENT_POSITION_FOLLOWING),
		other,
	);
}

test.describe('/dashboard — this week leads', () => {
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

	test('a planless account opens on this week against its recent average, with Add a run above the fold', async ({
		browser,
	}) => {
		for (const viewport of [
			{ width: 1280, height: 720 },
			{ width: 390, height: 844 },
		]) {
			const ctx = await browser.newContext({ storageState: user.storageStatePath, viewport });
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();
			try {
				await page.goto('/dashboard');
				const lead = page.getByTestId('dash-week-lead');
				await expect(lead).toBeVisible({ timeout: 15_000 });

				await expect(lead.getByTestId('dash-week-lead-distance')).toContainText(/1 activity/);
				await expect(lead.getByTestId('dash-week-lead-vs')).toContainText(/weekly average over the last \d weeks/i);
				await expect(lead.getByTestId('dash-week-lead-next')).toHaveCount(0);

				const add = lead.getByTestId('dash-week-lead-add');
				await expect(add).toHaveAttribute('href', '/runs/new');
				await expect(add).toBeInViewport();

				const statGrid = page.locator('.stat-grid');
				await expect(statGrid).toBeVisible();
				expect(await precedes(lead, statGrid)).toBe(true);
				await expect(page.getByTestId('dash-first-run')).toHaveCount(0);
			} finally {
				await ctx.close();
			}
		}
	});

	test.describe('with an active plan', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('the next session sits in the lead, ahead of the plan hero it does not replace', async ({ page }) => {
			await page.goto('/dashboard');
			const lead = page.getByTestId('dash-week-lead');
			await expect(lead).toBeVisible({ timeout: 15_000 });
			await expect(lead.getByTestId('dash-week-lead-next')).toBeVisible();
			await expect(lead.getByTestId('dash-week-lead-add')).toBeInViewport();

			const hero = page.locator('.plan-hero');
			await expect(hero).toBeVisible();
			expect(await precedes(lead, hero)).toBe(true);
		});
	});
});
