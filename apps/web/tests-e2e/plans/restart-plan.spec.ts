import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * "Restart this plan" (issue #1186, decisions § 2121): a fresh active copy on
 * a new start date, with the plan it replaces retired as abandoned and its
 * history kept. Runs as a saga user because the restart retires every active
 * plan its window overlaps, which would reach into other specs' plans on a
 * shared seeded user.
 */

const PLAN_NAME = 'e2e restart block';

async function seedPlan(userId: string, raceOffset: number): Promise<{ planId: string; doneId: string }> {
	const admin = getAdminClient();
	const plan = await readRow(
		'the seeded plan',
		admin
			.from('training_plans')
			.insert({
				user_id: userId,
				name: PLAN_NAME,
				goal_event: 'distance_10k',
				goal_distance_m: 10000,
				start_date: browserDate(-14),
				end_date: browserDate(-14 + 20),
				days_per_week: 3,
				status: 'active'
			})
			.select('id')
			.single()
	);
	let doneId = '';
	for (let i = 0; i < 3; i++) {
		const week = await readRow(
			`week ${i}`,
			admin
				.from('plan_weeks')
				.insert({ plan_id: plan.id, week_index: i, phase: 'base', target_volume_m: 5000 })
				.select('id')
				.single()
		);
		const wo = await readRow(
			`week ${i} workout`,
			admin
				.from('plan_workouts')
				.insert({
					week_id: week.id,
					scheduled_date: browserDate(-14 + i * 7 + 1),
					kind: 'easy',
					target_distance_m: 5000,
					manually_completed: i === 0
				})
				.select('id')
				.single()
		);
		if (i === 0) doneId = wo.id;
	}
	const raceWeek = await readRow(
		'the race week',
		admin.from('plan_weeks').select('id').eq('plan_id', plan.id).eq('week_index', raceOffset < 0 ? 0 : 2).single()
	);
	const { error } = await admin.from('plan_workouts').insert({
		week_id: raceWeek.id,
		scheduled_date: browserDate(raceOffset),
		kind: 'race',
		target_distance_m: 5000,
		race_name: 'Tune-up',
		race_priority: 'C'
	});
	if (error) throw error;
	return { planId: plan.id, doneId };
}

test.describe('restarting a plan', () => {
	let users: SagaUser[] = [];

	test.beforeAll(async () => {
		users = await createSagaUsers(2);
	});

	test.afterAll(async () => {
		await deleteSagaUsers(users);
	});

	test('the copy starts fresh on the picked date and the old plan is abandoned with its history', async ({
		browser
	}) => {
		const user = users[0];
		const { planId, doneId } = await seedPlan(user.id, -12);
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		await page.goto(`/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: PLAN_NAME })).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Adjust plan' }).first().click();
		await page.getByTestId('restart-plan-btn').click();
		const dialog = page.getByTestId('restart-plan-dialog');
		await expect(dialog.getByTestId('restart-start-date')).toHaveValue(browserDate(7));
		const message = dialog.getByTestId('restart-confirm-message');
		await expect(message).toContainText('This plan, and any active plan those dates overlap, is retired as abandoned');
		await expect(message).toContainText('Its weeks, workouts and run links are kept.');
		await expect(message).toContainText('Race day moves to');

		await dialog.getByTestId('restart-start-date').fill(browserDate(10));
		await expect(dialog.getByTestId('restart-start-date')).toHaveValue(browserDate(14));

		await dialog.getByTestId('restart-confirm').click();
		await expect(page.getByText('Plan restarted. This is your new copy.')).toBeVisible();
		await page.waitForURL((url) => /\/plans\/[0-9a-f-]{36}$/.test(url.pathname) && !url.pathname.endsWith(planId));
		const newId = page.url().split('/plans/')[1];
		await expect(page.getByRole('heading', { level: 1, name: PLAN_NAME })).toBeVisible();

		const admin = getAdminClient();
		const old = await readRow(
			'the source plan',
			admin.from('training_plans').select('status, start_date').eq('id', planId).single()
		);
		expect(old).toEqual({ status: 'abandoned', start_date: browserDate(-14) });
		const done = await readRow(
			'the source completion',
			admin.from('plan_workouts').select('manually_completed').eq('id', doneId).single()
		);
		expect(done.manually_completed).toBe(true);

		const copy = await readRow(
			'the copy',
			admin.from('training_plans').select('status, start_date, end_date').eq('id', newId).single()
		);
		expect(copy).toEqual({ status: 'active', start_date: browserDate(14), end_date: browserDate(34) });
		const copyWeeks = await readRows(
			'the copy weeks',
			admin
				.from('plan_weeks')
				.select('week_index, plan_workouts(kind, scheduled_date, manually_completed, completed_run_id, skipped_at)')
				.eq('plan_id', newId)
				.order('week_index')
		);
		expect(copyWeeks.map((w) => w.week_index)).toEqual([0, 1, 2]);
		const copyWorkouts = copyWeeks.flatMap((w) => w.plan_workouts);
		expect(copyWorkouts).toHaveLength(4);
		expect(copyWorkouts.every((w) => !w.manually_completed && !w.completed_run_id && !w.skipped_at)).toBe(true);
		expect(copyWorkouts.find((w) => w.kind === 'race')?.scheduled_date).toBe(browserDate(16));
		await ctx.close();
	});

	test('a plan whose race is still ahead is not restarted', async ({ browser }) => {
		const user = users[1];
		const { planId } = await seedPlan(user.id, 5);
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		await page.goto(`/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: PLAN_NAME })).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Adjust plan' }).first().click();
		await page.getByTestId('restart-plan-btn').click();
		const dialog = page.getByTestId('restart-plan-dialog');
		await expect(dialog.getByTestId('restart-race-ahead')).toContainText('is still ahead');
		await expect(dialog.getByTestId('restart-confirm')).toHaveCount(0);

		const plan = await readRow(
			'the plan',
			getAdminClient().from('training_plans').select('status').eq('id', planId).single()
		);
		expect(plan.status).toBe('active');
		await ctx.close();
	});
});
