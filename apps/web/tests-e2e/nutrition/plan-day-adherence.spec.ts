import { expect, test } from '../fixtures/mock-route';

import { browserDate, noonOnBrowserDay } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * /nutrition — the day view under a followed plan
 * (docs/features/nutrition_programming.md § Adherence, P1).
 *
 * A fresh user with no body metrics follows a seeded plan from six days ago,
 * so every target on the page is the plan's. Each viewed day exercises one
 * verdict: an off_target day names the macros that missed and which way, an
 * under-logged day reads as partial, a training day switches to the plan's
 * training targets, and a day before the plan started shows no panel at all.
 *
 * The error case runs as the seeded user: when the assignments read fails the
 * page refuses to draw the computed target as if no plan existed.
 */
test.describe('/nutrition — plan day adherence', () => {
	let user: SagaUser;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Plan Follower'] });
		const admin = getAdminClient();
		const { data: plan, error } = await admin
			.from('nutrition_plans')
			.insert({
				author_id: user.id,
				title: 'E2E Adherence Plan',
				target_calories: 2000,
				target_protein_g: 150,
				target_carbs_g: 200,
				target_fat_g: 70,
				training_calories: 2600,
				training_carbs_g: 300,
			})
			.select('id')
			.single();
		if (error || !plan) throw new Error(`seed plan failed: ${error?.message}`);
		const { error: aErr } = await admin.from('nutrition_plan_assignments').insert({
			plan_id: plan.id,
			client_id: user.id,
			assigned_by: user.id,
			start_date: browserDate(-6),
		});
		if (aErr) throw new Error(`seed assignment failed: ${aErr.message}`);
		const food = (offset: number, item: string, calories: number, p: number, c: number, f: number) => ({
			user_id: user.id,
			started_at: noonOnBrowserDay(offset),
			item_name: item,
			calories,
			protein_g: p,
			carbs_g: c,
			fat_g: f,
			meal_slot: 'lunch',
		});
		const { error: fErr } = await admin.from('food_log').insert([
			food(-1, 'E2E off-target day', 2100, 110, 210, 95),
			food(-2, 'E2E under-logged day', 500, 40, 50, 10),
			food(-5, 'E2E training day', 2500, 160, 290, 70),
			food(-7, 'E2E before the plan', 1800, 100, 200, 60),
		]);
		if (fErr) throw new Error(`seed food failed: ${fErr.message}`);
		const { error: gErr } = await admin
			.from('gym_workouts')
			.insert({ user_id: user.id, started_at: noonOnBrowserDay(-5), title: 'E2E lift', duration_s: 1800 });
		if (gErr) throw new Error(`seed gym failed: ${gErr.message}`);
	});

	test.afterAll(async () => {
		await deleteSagaUsers([user]);
	});

	test('each governed day carries its verdict, and a day before the plan has none', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto(`/nutrition?date=${browserDate(-1)}`);
			const verdict = page.getByTestId('plan-adherence-verdict');
			await expect(verdict).toHaveAttribute('data-verdict', 'off_target', { timeout: 10_000 });
			await expect(page.getByTestId('macro-rings')).toContainText('2100 / 2000 kcal');
			await expect(page.getByTestId('plan-adherence-calories')).toHaveAttribute('data-verdict', 'met');
			await expect(page.getByTestId('plan-adherence-protein')).toHaveAttribute('data-verdict', 'under');
			await expect(page.getByTestId('plan-adherence-protein')).toContainText('110 / 150 g');
			await expect(page.getByTestId('plan-adherence-carbs')).toHaveAttribute('data-verdict', 'met');
			await expect(page.getByTestId('plan-adherence-fat')).toHaveAttribute('data-verdict', 'over');
			await expect(page.getByTestId('plan-following')).toContainText('E2E Adherence Plan');

			await page.goto(`/nutrition?date=${browserDate(-2)}`);
			await expect(verdict).toHaveAttribute('data-verdict', 'partial', { timeout: 10_000 });
			await expect(page.getByTestId('plan-adherence-partial')).toBeVisible();

			await page.goto(`/nutrition?date=${browserDate(-5)}`);
			await expect(page.getByTestId('plan-training-day')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('macro-rings')).toContainText('2500 / 2600 kcal');
			await expect(verdict).toHaveAttribute('data-verdict', 'on_target');

			await page.goto(`/nutrition?date=${browserDate(-7)}`);
			await expect(page.locator('.meal-list li', { hasText: 'E2E before the plan' })).toBeVisible({
				timeout: 10_000,
			});
			await expect(page.getByTestId('plan-adherence')).toHaveCount(0);
			await expect(page.getByTestId('plan-following')).toHaveCount(0);
			await expect(page.getByTestId('no-targets')).toBeVisible();
		} finally {
			await ctx.close();
		}
	});

	test.describe('when the plan read fails', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('the page shows the load error rather than the computed target', async ({ page, mockRoute }) => {
			let failed = false;
			await mockRoute(page, '**/rest/v1/nutrition_plan_assignments**', async (route) => {
				if (!failed && route.request().method() === 'GET') {
					failed = true;
					await route.fulfill({
						status: 500,
						contentType: 'application/json',
						body: JSON.stringify({ message: 'simulated assignment read failure' }),
					});
					return;
				}
				await route.fallback();
			});

			await page.goto('/nutrition');
			await expect(page.getByTestId('nutrition-load-error')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('macro-rings')).toHaveCount(0);

			await page.getByRole('button', { name: 'Retry' }).click();
			await expect(page.getByTestId('nutrition-load-error')).toHaveCount(0, { timeout: 10_000 });
			await expect(page.getByTestId('macro-rings')).toBeVisible();
		});
	});
});
