import { expect, test } from '../fixtures/test';

import { browserDate, browserDayStart } from '../fixtures/dates';
import { readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deletePlan } from '../fixtures/simulate';
import { USER_B } from '../fixtures/users';

/**
 * Resuming a paused plan pushes the weeks the runner had not started back by
 * the whole weeks it sat paused (issue #1186), so they come back as upcoming
 * rather than missed. Runs as USER_B on a plan this file seeds and deletes.
 */

const PLAN_NAME = 'e2e resume block';

async function deletePlans(): Promise<void> {
	const rows = await readRows(
		'USER_B resume plans',
		getAdminClient().from('training_plans').select('id').eq('user_id', USER_B.id).like('name', 'e2e resume%')
	);
	for (const row of rows) await deletePlan(row.id);
}

/// Six weeks from 28 days ago, paused 25 days ago (in week 0), one easy run a
/// week on each week's second day.
async function seedPausedPlan(): Promise<string> {
	const admin = getAdminClient();
	const plan = await readRow(
		'the seeded plan',
		admin
			.from('training_plans')
			.insert({
				user_id: USER_B.id,
				name: PLAN_NAME,
				goal_event: 'distance_10k',
				goal_distance_m: 10000,
				start_date: browserDate(-28),
				end_date: browserDate(-28 + 41),
				days_per_week: 3,
				status: 'paused',
				paused_at: browserDayStart(-25)
			})
			.select('id')
			.single()
	);
	for (let i = 0; i < 6; i++) {
		const week = await readRow(
			`week ${i}`,
			admin
				.from('plan_weeks')
				.insert({ plan_id: plan.id, week_index: i, phase: 'base', target_volume_m: 5000 })
				.select('id')
				.single()
		);
		const { error } = await admin.from('plan_workouts').insert({
			week_id: week.id,
			scheduled_date: browserDate(-28 + i * 7 + 1),
			kind: 'easy',
			target_distance_m: 5000
		});
		if (error) throw error;
	}
	return plan.id;
}

test.describe('resuming a paused plan', () => {
	test.use({ storageState: USER_B.storageStatePath });
	test.beforeEach(deletePlans);
	test.afterEach(deletePlans);

	test('the weeks not yet started move back by the weeks it sat paused', async ({ page }) => {
		const planId = await seedPausedPlan();
		await page.goto(`/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: PLAN_NAME })).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Adjust plan' }).first().click();
		await page.getByRole('button', { name: /Resume plan/ }).click();
		await expect(page.getByText(/move back 4 weeks/)).toBeVisible();
		await page.getByRole('button', { name: 'Apply' }).click();
		await expect(page.getByText('Plan resumed and pushed back 4 weeks.')).toBeVisible();

		const admin = getAdminClient();
		const plan = await readRow(
			'the resumed plan',
			admin.from('training_plans').select('status, paused_at, start_date, end_date').eq('id', planId).single()
		);
		expect(plan).toEqual({
			status: 'active',
			paused_at: null,
			start_date: browserDate(-28),
			end_date: browserDate(-28 + 41 + 28)
		});
		const weeks = await readRows(
			'its weeks',
			admin.from('plan_weeks').select('week_index, plan_workouts(scheduled_date)').eq('plan_id', planId).order('week_index')
		);
		expect(weeks.map((w) => w.week_index)).toEqual([0, 5, 6, 7, 8, 9]);
		expect(weeks[0].plan_workouts[0].scheduled_date).toBe(browserDate(-27));
		expect(weeks[1].plan_workouts[0].scheduled_date).toBe(browserDate(-27 + 7 + 28));
	});

	test('Home offers the paused plan, and its card opens the resume confirm', async ({ page }) => {
		const planId = await seedPausedPlan();
		await page.goto('/dashboard');
		const card = page.getByTestId('dash-paused-plan');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card).toContainText(PLAN_NAME);

		await card.click();
		await page.waitForURL(new RegExp(`/plans/${planId}`));
		await expect(page.getByText(/move back 4 weeks/)).toBeVisible();
		await expect(page).not.toHaveURL(/resume=1/);
		await page.getByRole('button', { name: 'Apply' }).click();
		await expect(page.getByText('Plan resumed and pushed back 4 weeks.')).toBeVisible();
	});
});
