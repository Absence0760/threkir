import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] Adjust plan (#902 §3). Four controls used to change the plan —
 * Shift dates, Re-plan remaining weeks, Adaptive re-plan, Pause plan — side by
 * side with nothing saying how they differed. They are now one Adjust plan
 * dialog that explains each option in a line, and every option opens the same
 * flow its old button did. The flows themselves are pinned by bulk-ops,
 * replan, adaptive-replan and cycle-plan-adjust; this pins the entry point:
 * all four are listed with an explanation, each reaches its flow, and nothing
 * is written until that flow is confirmed.
 *
 * The plan is ACTIVE so the lifecycle option reads "Pause plan", which means
 * displacing the seeded active plan for the duration and restoring it after.
 * The weeks are the adaptive-replan seed (three finished weeks far under plan
 * plus a missed long run), so both re-plan flows open a preview.
 */

const dayMs = 24 * 3600 * 1000;
const iso = (d: Date) => d.toISOString().slice(0, 10);

test.describe('/plans/[id] Adjust plan', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('lists all four options with an explanation, and each opens its flow', async ({ page }) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const weekIds = [crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID()];
		const startIso = iso(new Date(Date.now() - 21 * dayMs));
		let displacedActiveIds: string[] = [];
		try {
			const { data: displaced } = await admin
				.from('training_plans')
				.select('id')
				.eq('user_id', USER_A.id)
				.eq('status', 'active');
			displacedActiveIds = (displaced ?? []).map((p) => p.id as string);
			await admin
				.from('training_plans')
				.update({ status: 'completed' })
				.eq('user_id', USER_A.id)
				.eq('status', 'active');

			await admin.from('training_plans').insert({
				id: planId, user_id: USER_A.id, name: 'e2e adjust plan', goal_event: 'distance_full',
				goal_distance_m: 42195, goal_time_seconds: null, start_date: startIso,
				end_date: iso(new Date(Date.now() + 60 * dayMs)), status: 'active', days_per_week: 5
			});
			await admin.from('plan_weeks').insert(
				weekIds.map((id, i) => ({ id, plan_id: planId, week_index: i, phase: 'build', target_volume_m: 200_000 }))
			);
			await admin.from('plan_workouts').insert([
				{ week_id: weekIds[0], scheduled_date: iso(new Date(Date.now() - 17 * dayMs)), kind: 'long', target_distance_m: 28_000 },
				{ week_id: weekIds[3], scheduled_date: iso(new Date(Date.now() + 3 * dayMs)), kind: 'long', target_distance_m: 22_000 }
			]);

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e adjust plan' }))
				.toBeVisible({ timeout: 10_000 });

			for (const name of ['Shift dates', 'Re-plan remaining weeks', 'Adaptive re-plan', 'Pause plan']) {
				await expect(page.getByRole('button', { name })).toHaveCount(0);
			}

			const adjust = page.getByRole('button', { name: 'Adjust plan' });
			const dialog = page.getByTestId('adjust-plan-dialog');
			const confirm = page.getByTestId('bulk-confirm-dialog');
			const preview = page.locator('.replan-preview');

			await adjust.click();
			await expect(dialog).toBeVisible();
			await expect(dialog.getByRole('button', { name: 'Shift dates' }))
				.toHaveAccessibleDescription(/race date.*Use it when/);
			await expect(dialog.getByRole('button', { name: 'Re-plan remaining weeks' }))
				.toHaveAccessibleDescription(/missed long run.*Use it when/);
			await expect(dialog.getByRole('button', { name: 'Adaptive re-plan' }))
				.toHaveAccessibleDescription(/last three finished weeks.*Use it when/);
			await expect(dialog.getByRole('button', { name: 'Pause plan' }))
				.toHaveAccessibleDescription(/without deleting anything.*Use it for/);

			await dialog.getByLabel('Days to shift (negative moves earlier)').fill('7');
			await dialog.getByRole('button', { name: 'Shift dates' }).click();
			await expect(dialog).toBeHidden();
			await expect(confirm).toContainText('Shift the whole plan?');
			await confirm.getByRole('button', { name: 'Cancel' }).click();
			await expect(confirm).toBeHidden();

			await adjust.click();
			await dialog.getByRole('button', { name: 'Re-plan remaining weeks' }).click();
			await expect(dialog).toBeHidden();
			await expect(preview).toContainText(/make up a missed long run/i);
			await expect(preview.getByRole('heading', { name: 'Proposed changes' })).toBeFocused();
			await expect(preview.locator('.replan-adaptive-badge')).toHaveCount(0);
			await preview.getByRole('button', { name: 'Cancel' }).click();
			await expect(preview).toHaveCount(0);

			await adjust.click();
			await dialog.getByRole('button', { name: 'Adaptive re-plan' }).click();
			await expect(dialog).toBeHidden();
			await expect(preview.locator('.replan-adaptive-badge')).toHaveText(/under your plan/i);
			await preview.getByRole('button', { name: 'Cancel' }).click();
			await expect(preview).toHaveCount(0);

			await adjust.click();
			await dialog.getByRole('button', { name: 'Pause plan' }).click();
			await expect(dialog).toBeHidden();
			await expect(confirm).toContainText('Pause this plan?');
			await confirm.getByRole('button', { name: 'Cancel' }).click();
			await expect(confirm).toBeHidden();

			const row = (await admin.from('training_plans').select('status, start_date').eq('id', planId).single()).data;
			expect(row).toEqual({ status: 'active', start_date: startIso });
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
			if (displacedActiveIds.length) {
				await admin.from('training_plans').update({ status: 'active' }).in('id', displacedActiveIds);
			}
		}
	});
});
