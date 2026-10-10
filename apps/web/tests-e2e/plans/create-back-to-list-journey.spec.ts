import { expect, test } from '@playwright/test';

import { browserDate } from '../fixtures/dates';
import { deletePlan, setPlanStatus } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

/**
 * Create a plan, then return to the plans list the way a user does.
 *
 * plans/create.spec.ts walks create → abandon → delete, but re-enters
 * /plans with page.goto after the create, which mounts a fresh list.
 * The detail page's "All plans" link does not: when the plan was opened
 * from /plans it calls history.back(), and /plans repaints from its
 * SvelteKit snapshot (plans + statusFilter) captured before the create.
 * This spec walks the click path — Runs in the sidebar, the Plans
 * surface tab, New plan, Create, All plans — and pins that the new plan
 * is on the list the user lands back on, as the active plan, and that
 * the list's own abandon + delete then work on it.
 *
 * The create demotes the seed's active plan; afterEach restores it and
 * deletes the new plan if the UI delete never ran.
 */

test.describe('/plans — create then back to the list', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let plantedPlanId: string | null = null;

	test.afterEach(async () => {
		if (plantedPlanId) {
			try {
				await deletePlan(plantedPlanId);
			} catch (_) {
				/* best-effort */
			}
			plantedPlanId = null;
		}
		try {
			await setPlanStatus(SEED_PLAN_ID, 'active');
		} catch (_) {
			/* best-effort */
		}
	});

	test('sidebar → Plans tab → New plan → create → All plans lists it as active → abandon → delete', async ({
		page
	}) => {
		const name = `e2e-plan-back ${Date.now()}`;

		await test.step('reach /plans by clicking', async () => {
			await page.goto('/dashboard');
			await page.locator('nav.sidebar').getByRole('link', { name: 'Runs', exact: true }).click();
			await page.waitForURL(/\/runs$/, { timeout: 10_000 });
			await page
				.getByRole('navigation', { name: /Run surface sections/ })
				.getByRole('link', { name: /^Plans$/ })
				.click();
			await page.waitForURL(/\/plans$/, { timeout: 10_000 });
			// The seed plan's card proves the list loaded before we leave it,
			// so the snapshot "All plans" restores is a populated one.
			await expect(page.locator(`a.card[href="/plans/${SEED_PLAN_ID}"]`)).toBeVisible({
				timeout: 10_000
			});
		});

		await test.step('create a plan from the New plan modal', async () => {
			await page.getByRole('button', { name: /New plan/ }).first().click();
			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });
			await modal.getByPlaceholder('Autumn half marathon').fill(name);
			await modal.locator('input[type="date"]').first().fill(browserDate(7));

			const submit = modal.getByRole('button', { name: /Create plan/ });
			await expect(submit).toBeEnabled({ timeout: 5_000 });
			await submit.click();

			const replace = page.locator('.modal.modal-narrow', {
				hasText: /Replace your active plan/
			});
			await expect(replace).toBeVisible({ timeout: 5_000 });
			await replace.getByRole('button', { name: 'Replace plan' }).click();

			await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
			plantedPlanId = page.url().match(/\/plans\/([0-9a-f-]+)$/)![1];
			await expect(page.getByRole('heading', { level: 1, name })).toBeVisible({
				timeout: 10_000
			});
		});

		await test.step('All plans returns to a list that holds the new plan as active', async () => {
			await page.getByRole('link', { name: /All plans/ }).first().click();
			await page.waitForURL(/\/plans$/, { timeout: 10_000 });

			const card = page.locator(`a.card[href="/plans/${plantedPlanId}"]`);
			await expect(
				card,
				'the plan just created must be in the list "All plans" returns to'
			).toBeVisible({ timeout: 10_000 });
			await expect(card).toContainText(name);
			await expect(card.getByRole('button', { name: 'Abandon', exact: true })).toBeVisible();

			// The replaced seed plan is no longer the active one.
			await expect(
				page
					.locator(`a.card[href="/plans/${SEED_PLAN_ID}"]`)
					.getByRole('button', { name: 'Abandon', exact: true })
			).toHaveCount(0);
		});

		await test.step('abandon then delete the new plan from its card', async () => {
			const card = page.locator(`a.card[href="/plans/${plantedPlanId}"]`);
			await card.getByRole('button', { name: 'Abandon', exact: true }).click();
			const abandon = page.locator('.modal', { hasText: 'Abandon plan' });
			await expect(abandon).toBeVisible({ timeout: 5_000 });
			await abandon.getByRole('button', { name: 'Abandon', exact: true }).click();
			await expect(abandon).toHaveCount(0);

			await card.getByRole('button', { name: 'Delete', exact: true }).click();
			const del = page.locator('.modal', { hasText: 'Delete plan' });
			await expect(del).toBeVisible({ timeout: 5_000 });
			await del.getByRole('button', { name: 'Delete', exact: true }).click();
			await expect(del).toHaveCount(0);
			await expect(card).toHaveCount(0, { timeout: 10_000 });
			plantedPlanId = null;
		});
	});
});
