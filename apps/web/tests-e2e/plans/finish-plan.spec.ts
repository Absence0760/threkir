import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deletePlan } from '../fixtures/simulate';
import { USER_B } from '../fixtures/users';

/**
 * Nothing writes `completed` when a plan's end date passes, so an ended plan
 * kept reading as the runner's plan indefinitely: a rest-day hero, "No more
 * sessions scheduled" in the week lead. Home and the plan itself now ask the
 * runner to finish it, and finishing files it under Completed (issue #1186).
 */
const NAME_PREFIX = 'e2e finish plan';

async function deleteFinishPlans(): Promise<void> {
	const rows = await readRows(
		'USER_B finish-plan rows',
		getAdminClient().from('training_plans').select('id').eq('user_id', USER_B.id).like('name', `${NAME_PREFIX}%`)
	);
	for (const row of rows) await deletePlan(row.id);
}

async function plantEndedPlan(name: string, endOffsetDays: number): Promise<string> {
	const admin = getAdminClient();
	const planId = crypto.randomUUID();
	const weekId = crypto.randomUUID();
	const { error } = await admin.from('training_plans').insert({
		id: planId,
		user_id: USER_B.id,
		name,
		goal_event: 'distance_10k',
		goal_distance_m: 10_000,
		start_date: browserDate(endOffsetDays - 13),
		end_date: browserDate(endOffsetDays),
		days_per_week: 4,
		status: 'active'
	});
	if (error) throw error;
	const { error: weekErr } = await admin
		.from('plan_weeks')
		.insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 10_000 });
	if (weekErr) throw weekErr;
	const { error: woErr } = await admin
		.from('plan_workouts')
		.insert({ week_id: weekId, scheduled_date: browserDate(endOffsetDays), kind: 'easy', target_distance_m: 5_000 });
	if (woErr) throw woErr;
	return planId;
}

async function status(id: string): Promise<string> {
	return (
		await readRow(`plan ${id}`, getAdminClient().from('training_plans').select('status').eq('id', id).single())
	).status;
}

test.describe('finishing a plan whose dates have run out', () => {
	test.use({ storageState: USER_B.storageStatePath });
	test.beforeEach(deleteFinishPlans);
	test.afterEach(deleteFinishPlans);

	test('Home asks to finish an ended plan, and finishing files it as completed', async ({ page }) => {
		const planId = await plantEndedPlan(`${NAME_PREFIX} home`, -2);
		await page.goto('/dashboard');
		const prompt = page.getByTestId('finish-plan-prompt');
		await expect(prompt).toBeVisible({ timeout: 10_000 });
		await expect(prompt).toContainText(`${NAME_PREFIX} home has ended`);

		await prompt.getByRole('button', { name: 'Finish plan' }).click();
		await expect(prompt).toHaveCount(0, { timeout: 10_000 });
		expect(await status(planId)).toBe('completed');
	});

	test('a plan on its last day is not finished yet', async ({ page }) => {
		const planId = await plantEndedPlan(`${NAME_PREFIX} last day`, 0);
		await page.goto(`/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: `${NAME_PREFIX} last day` })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByTestId('finish-plan-prompt')).toHaveCount(0);
	});

	test('the plan page offers Finish plan once the plan has ended', async ({ page }) => {
		const planId = await plantEndedPlan(`${NAME_PREFIX} detail`, -1);
		await page.goto(`/plans/${planId}`);
		const prompt = page.getByTestId('finish-plan-prompt');
		await expect(prompt).toBeVisible({ timeout: 10_000 });
		await prompt.getByRole('button', { name: 'Finish plan' }).click();
		await expect(prompt).toHaveCount(0, { timeout: 10_000 });
		expect(await status(planId)).toBe('completed');
	});
});
