import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * /nutrition — meal plans, nutrition programming P1
 * (docs/features/nutrition_programming.md, migration 20270815000001).
 *
 * A fresh user with no body metrics, so the computed target is absent and the
 * only targets on the page can be the plan's. The loop: the Plans section
 * self-hides at zero plans, a plan is built from the no-targets block and
 * followed from today, the day view seeds its rings from it and shows the
 * adherence panel, and stopping from the detail page puts the day back. An
 * out-of-range calorie target is refused in the editor without a write.
 */
test.describe('/nutrition — meal plan builder', () => {
	let user: SagaUser;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Plan Builder'] });
	});

	test.afterAll(async () => {
		await deleteSagaUsers([user]);
	});

	test('build a plan, follow it from today, then stop following', async ({ browser }) => {
		const admin = getAdminClient();
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		const title = `E2E Build ${Date.now()}`;
		try {
			await page.goto('/nutrition');
			await expect(page.getByTestId('no-targets')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('nutrition-plans')).toHaveCount(0);
			await expect(page.getByTestId('plan-adherence')).toHaveCount(0);

			await page.getByTestId('plan-from-scratch').click();
			const dialog = page.getByRole('dialog', { name: 'New meal plan' });
			await expect(dialog).toBeVisible();

			await dialog.getByTestId('plan-title').fill(title);
			await dialog.getByTestId('plan-calories').fill('900');
			await dialog.getByTestId('plan-save').click();
			await expect(dialog.getByTestId('plan-error')).toContainText('1200');
			expect(
				(await admin.from('nutrition_plans').select('id').eq('author_id', user.id)).data ?? [],
			).toHaveLength(0);

			await dialog.getByTestId('plan-calories').fill('2000');
			await dialog.getByTestId('plan-protein').fill('150');
			await expect(dialog.getByTestId('plan-follow-today')).toBeChecked();
			await dialog.getByTestId('plan-save').click();
			await expect(dialog).toBeHidden({ timeout: 10_000 });

			const row = page.getByTestId('nutrition-plans').getByTestId('nutrition-plan-row');
			await expect(row).toHaveCount(1, { timeout: 10_000 });
			await expect(row.getByTestId('plan-following-badge')).toBeVisible();
			await expect(page.getByTestId('plan-following')).toContainText(title);
			await expect(page.getByTestId('macro-rings')).toContainText('0 / 2000 kcal');
			await expect(page.getByTestId('plan-adherence-verdict')).toHaveAttribute('data-verdict', 'partial');

			const plans = (
				await admin
					.from('nutrition_plans')
					.select('id, target_calories, target_protein_g, target_fat_g')
					.eq('author_id', user.id)
			).data ?? [];
			expect(plans).toHaveLength(1);
			expect(Number(plans[0].target_calories)).toBe(2000);
			expect(Number(plans[0].target_protein_g)).toBe(150);
			expect(plans[0].target_fat_g).toBeNull();
			const assignments = (
				await admin
					.from('nutrition_plan_assignments')
					.select('plan_id, client_id, assigned_by, start_date, status')
					.eq('client_id', user.id)
			).data ?? [];
			expect(assignments).toEqual([
				{
					plan_id: plans[0].id,
					client_id: user.id,
					assigned_by: user.id,
					start_date: browserDate(0),
					status: 'active',
				},
			]);

			await row.locator('a').click();
			await expect(page).toHaveURL(new RegExp(`/nutrition/plans/${plans[0].id}$`));
			await expect(page.getByTestId('plan-detail-title')).toHaveText(title);
			await expect(page.getByTestId('plan-detail-following')).toBeVisible();
			await page.getByTestId('plan-stop').click();
			await expect(page.getByTestId('plan-detail-follow')).toBeVisible({ timeout: 10_000 });
			// It started today, so it governed no finished day and is removed.
			await expect
				.poll(
					async () =>
						((await admin.from('nutrition_plan_assignments').select('id').eq('client_id', user.id)).data ?? [])
							.length,
				)
				.toBe(0);

			await page.goto('/nutrition');
			await expect(page.getByTestId('no-targets')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('plan-following')).toHaveCount(0);
			await expect(page.getByTestId('plan-adherence')).toHaveCount(0);
			await expect(page.getByTestId('nutrition-plans').getByTestId('plan-follow')).toBeVisible();
		} finally {
			await admin.from('nutrition_plans').delete().eq('author_id', user.id);
			await ctx.close();
		}
	});

	test('a plan id that does not resolve reads as not found, not as an error', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto('/nutrition/plans/00000000-0000-4000-8000-000000000000');
			await expect(page.getByTestId('plan-not-found')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('plan-load-error')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
