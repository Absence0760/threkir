import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /nutrition — "Save as plan", the P1 adoption wedge
 * (docs/features/nutrition_programming.md § Web UI).
 *
 * The seeded user has body metrics, so the computed target exists and the day
 * view offers to promote it. The editor opens seeded with the REST-day target
 * (never the exercise add-on), saved without following it; the Plans section
 * then appears with a Follow action and the day stays on the computed target.
 */
test.describe('/nutrition — save as plan', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('promote the computed target into a plan without following it', async ({ page }) => {
		const admin = getAdminClient();
		const title = `E2E Saved Targets ${Date.now()}`;
		try {
			await page.goto('/nutrition');
			const wedge = page.getByTestId('save-as-plan');
			await expect(wedge).toBeVisible({ timeout: 10_000 });
			// The rest-day target is the ring's target less today's workout
			// add-on, which the breakdown line states whenever there is one.
			const meta = await page.getByTestId('macro-rings').locator('.card-meta').first().innerText();
			const ringTarget = Number(meta.match(/\/\s*(\d+)\s*kcal/)?.[1]);
			const breakdown = page.getByTestId('goal-breakdown');
			const restDay =
				(await breakdown.count()) > 0
					? Number((await breakdown.innerText()).match(/(\d+)/)?.[1])
					: ringTarget;
			expect(restDay).toBeGreaterThanOrEqual(1200);
			await wedge.click();

			const dialog = page.getByRole('dialog', { name: "Save today's targets as a plan" });
			await expect(dialog).toBeVisible();
			const seeded = Number(await dialog.getByTestId('plan-calories').inputValue());
			expect(seeded).toBe(restDay);
			expect(Number(await dialog.getByTestId('plan-protein').inputValue())).toBeGreaterThan(0);

			await dialog.getByTestId('plan-title').fill(title);
			await dialog.getByTestId('plan-follow-today').uncheck();
			await dialog.getByTestId('plan-save').click();
			await expect(dialog).toBeHidden({ timeout: 10_000 });

			const row = page.getByTestId('nutrition-plans').locator('[data-testid="nutrition-plan-row"]', {
				hasText: title,
			});
			await expect(row).toBeVisible({ timeout: 10_000 });
			await expect(row.getByTestId('plan-follow')).toBeVisible();
			await expect(page.getByTestId('plan-following')).toHaveCount(0);
			await expect(page.getByTestId('save-as-plan')).toBeVisible();

			const saved = (
				await admin
					.from('nutrition_plans')
					.select('id, target_calories, goal_phase')
					.eq('author_id', USER_A.id)
					.eq('title', title)
			).data ?? [];
			expect(saved).toHaveLength(1);
			expect(Number(saved[0].target_calories)).toBe(seeded);
			expect(
				(await admin.from('nutrition_plan_assignments').select('id').eq('plan_id', saved[0].id)).data ?? [],
			).toHaveLength(0);
		} finally {
			await admin.from('nutrition_plans').delete().eq('author_id', USER_A.id).eq('title', title);
		}
	});
});
