import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deletePlan } from '../fixtures/simulate';
import { USER_B } from '../fixtures/users';

/**
 * Editing a plan's goal time re-derives the paces still ahead (issue #1186):
 * the plan editor writes the goal and the scaled paces in one call
 * (`set_plan_goal_time`). Runs as USER_B on an imported throwaway plan, so the
 * seeded plans are never touched; every plan this file makes is deleted.
 */

const PLAN_NAME = 'e2e repace block';

async function deletePlans(): Promise<void> {
	const rows = await readRows(
		'USER_B repace plans',
		getAdminClient().from('training_plans').select('id').eq('user_id', USER_B.id).like('name', 'e2e repace%')
	);
	for (const row of rows) await deletePlan(row.id);
}

async function planState(): Promise<{ goal: number | null; paces: Record<string, number | null> }> {
	const admin = getAdminClient();
	const plan = await readRow(
		'the imported plan',
		admin.from('training_plans').select('id, goal_time_seconds').eq('user_id', USER_B.id).eq('name', PLAN_NAME).single()
	);
	const weeks = await readRows('its weeks', admin.from('plan_weeks').select('id').eq('plan_id', plan.id));
	const workouts = await readRows(
		'its workouts',
		admin
			.from('plan_workouts')
			.select('kind, target_pace_sec_per_km')
			.in('week_id', weeks.map((w) => w.id))
	);
	return {
		goal: plan.goal_time_seconds,
		paces: Object.fromEntries(workouts.map((w) => [w.kind, w.target_pace_sec_per_km]))
	};
}

test.describe('a goal-time edit re-derives the plan paces', () => {
	test.use({ storageState: USER_B.storageStatePath });
	test.beforeEach(deletePlans);
	test.afterEach(deletePlans);

	test('a faster goal tightens every pace still ahead, in the same save', async ({ page }) => {
		await page.goto('/plans/new');
		await expect(page.locator('.week-item').first()).toBeVisible({ timeout: 10_000 });
		await page.getByText('Import a plan', { exact: true }).click();
		await page.getByRole('textbox', { name: 'Import a plan' }).fill(
			[
				`# ${PLAN_NAME}`,
				'- Goal event: distance_half',
				'- Goal distance: 21.10 km',
				'- Goal time: 2:00:00',
				`- Start date: ${browserDate(0)}`,
				'',
				'| Week | Date | Type | Distance | Pace | Notes |',
				'| --- | --- | --- | --- | --- | --- |',
				`| 1 | ${browserDate(2)} | easy | 8.00 km | 5:30 | |`,
				`| 1 | ${browserDate(4)} | tempo | 8.00 km | 5:00 | |`
			].join('\n')
		);
		await page.getByRole('button', { name: 'Load plan' }).click();
		const submit = page.getByRole('button', { name: /Create plan/ });
		await expect(submit).toBeEnabled({ timeout: 5_000 });
		await submit.click();
		await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });

		expect(await planState()).toEqual({ goal: 7200, paces: { easy: 330, tempo: 300 } });

		await page.getByRole('button', { name: /Edit plan/ }).click();
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });
		const [hours, minutes] = [modal.getByPlaceholder('h', { exact: true }), modal.getByPlaceholder('m', { exact: true })];
		await hours.fill('1');
		await minutes.fill('48');
		await modal.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(modal).toHaveCount(0);
		await expect(page.getByText('Paces re-derived for 2 upcoming workouts')).toBeVisible();

		// 1:48 over 2:00 is a 0.9 goal-pace ratio.
		expect(await planState()).toEqual({ goal: 6480, paces: { easy: 297, tempo: 270 } });
	});
});
