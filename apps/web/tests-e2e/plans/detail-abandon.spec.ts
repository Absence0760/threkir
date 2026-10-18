import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] Abandon (#1186). A paused plan used to be abandonable only from
 * the list; detail had no way out. Adjust plan now lists Abandon for an active
 * or paused plan, behind a ConfirmDialog that says what is kept, and the page
 * reflects the new status once it lands. The plan is PAUSED so the seeded
 * active plan is left alone.
 */

const dayMs = 24 * 3600 * 1000;
const iso = (d: Date) => d.toISOString().slice(0, 10);

test.describe('/plans/[id] Abandon', () => {
	test.use({ storageState: USER_A.storageStatePath });

	async function seedPausedPlan(name: string): Promise<{ planId: string; weekId: string }> {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const weekId = crypto.randomUUID();
		await admin.from('training_plans').insert({
			id: planId, user_id: USER_A.id, name, goal_event: 'distance_10k',
			goal_distance_m: 10_000, goal_time_seconds: null,
			start_date: iso(new Date(Date.now() - 7 * dayMs)),
			end_date: iso(new Date(Date.now() + 49 * dayMs)), status: 'paused', days_per_week: 4
		});
		await admin.from('plan_weeks').insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 30_000 });
		await admin.from('plan_workouts').insert({
			week_id: weekId, scheduled_date: iso(new Date(Date.now() + 2 * dayMs)), kind: 'easy', target_distance_m: 6_000
		});
		return { planId, weekId };
	}

	test('a paused plan can be abandoned from detail, and the page reflects it', async ({ page }) => {
		const admin = getAdminClient();
		const { planId, weekId } = await seedPausedPlan('e2e abandon paused');
		try {
			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e abandon paused' }))
				.toBeVisible({ timeout: 10_000 });

			const adjust = page.getByRole('button', { name: 'Adjust plan' });
			const dialog = page.getByTestId('adjust-plan-dialog');
			const confirm = page.getByTestId('abandon-confirm-dialog');

			await adjust.click();
			const abandon = dialog.getByRole('button', { name: 'Abandon plan' });
			await expect(abandon).toHaveAccessibleDescription(/weeks, workouts and linked runs are kept/);
			await abandon.click();
			await expect(dialog).toBeHidden();
			await expect(confirm).toContainText('Its weeks, workouts and linked runs are kept.');

			await confirm.getByRole('button', { name: 'Cancel' }).click();
			await expect(confirm).toBeHidden();
			expect((await admin.from('training_plans').select('status').eq('id', planId).single()).data)
				.toEqual({ status: 'paused' });

			await adjust.click();
			await dialog.getByRole('button', { name: 'Abandon plan' }).click();
			await confirm.getByRole('button', { name: 'Abandon' }).click();
			await expect(confirm).toBeHidden();

			await expect.poll(async () =>
				(await admin.from('training_plans').select('status').eq('id', planId).single()).data?.status
			).toBe('abandoned');
			const kept = await admin.from('plan_workouts').select('id').eq('week_id', weekId);
			expect(kept.data).toHaveLength(1);

			await adjust.click();
			await expect(dialog).toBeVisible();
			await expect(dialog.getByRole('button', { name: 'Abandon plan' })).toHaveCount(0);
			await expect(dialog.getByRole('button', { name: 'Resume plan' })).toHaveCount(0);
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});

	test('a failed abandon keeps the dialog open and says so', async ({ page }) => {
		const admin = getAdminClient();
		const { planId } = await seedPausedPlan('e2e abandon fails');
		try {
			await page.route('**/rest/v1/training_plans**', async (route) => {
				if (route.request().method() === 'PATCH') {
					await route.fulfill({
						status: 500,
						contentType: 'application/json',
						body: JSON.stringify({ message: 'simulated failure' })
					});
					return;
				}
				await route.fallback();
			});

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e abandon fails' }))
				.toBeVisible({ timeout: 10_000 });
			await page.getByRole('button', { name: 'Adjust plan' }).click();
			await page.getByTestId('adjust-plan-dialog').getByRole('button', { name: 'Abandon plan' }).click();
			const confirm = page.getByTestId('abandon-confirm-dialog');
			await confirm.getByRole('button', { name: 'Abandon' }).click();

			await expect(page.locator('.toast-error')).toBeVisible({ timeout: 5_000 });
			await expect(confirm).toBeVisible();
			expect((await admin.from('training_plans').select('status').eq('id', planId).single()).data)
				.toEqual({ status: 'paused' });
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});
});
