import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { browserDate, noonOnBrowserDay } from '../fixtures/dates';
import { readRow, readRows } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { deletePlan, deleteRun, insertRun } from '../fixtures/simulate';
import { USER_B } from '../fixtures/users';

/**
 * A run done a day before its planned workout is never linked silently: the
 * database matches a run on its own local day only (migration
 * 20270901000001), and run detail asks about a workout within two days
 * (`plan_workout_link_candidates`, 20270901000002). Yes links it; "Not this
 * one" moves on, links nothing, and is not asked again. USER_B has no plan of their own, so the
 * spec owns the whole plan it asks about.
 */

test.describe('Run detail cross-day workout prompt', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let planId: string | null = null;
	let runId: string | null = null;
	let workoutId = '';
	let laterWorkoutId = '';

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
		const admin = getAdminClient();
		const { data: plan, error } = await admin
			.from('training_plans')
			.insert({
				user_id: USER_B.id,
				name: 'e2e cross-day prompt',
				goal_event: 'distance_10k',
				goal_distance_m: 10_000,
				start_date: browserDate(-3),
				end_date: browserDate(20),
				status: 'active'
			})
			.select('id')
			.single();
		if (error) throw error;
		planId = plan.id as string;
		const { data: week, error: weekErr } = await admin
			.from('plan_weeks')
			.insert({ plan_id: planId, week_index: 0 })
			.select('id')
			.single();
		if (weekErr) throw weekErr;
		const { data: workouts, error: woErr } = await admin
			.from('plan_workouts')
			.insert([
				{ week_id: week.id, scheduled_date: browserDate(1), kind: 'long', target_distance_m: 10_000 },
				{ week_id: week.id, scheduled_date: browserDate(2), kind: 'easy', target_distance_m: 8_000 }
			])
			.select('id, scheduled_date');
		if (woErr) throw woErr;
		const rows = workouts as { id: string; scheduled_date: string }[];
		workoutId = rows.find((r) => r.scheduled_date === browserDate(1))!.id;
		laterWorkoutId = rows.find((r) => r.scheduled_date === browserDate(2))!.id;

		runId = await insertRun({
			user_id: USER_B.id,
			started_at: noonOnBrowserDay(0),
			duration_s: 3_300,
			distance_m: 10_200
		});
	});

	test.afterEach(async () => {
		if (runId) await deleteRun(runId).catch(() => {});
		if (planId) await deletePlan(planId).catch(() => {});
		runId = null;
		planId = null;
	});

	test('asks about tomorrow\'s workout, and yes links it', async ({ page }) => {
		const admin = getAdminClient();
		const before = await readRow(
			'plan_workouts by id',
			admin.from('plan_workouts').select('completed_run_id').eq('id', workoutId).single()
		);
		expect(before.completed_run_id).toBeNull();

		await page.goto(`/runs/${runId}`);
		const prompt = page.getByTestId('plan-link-prompt');
		await expect(prompt).toBeVisible({ timeout: 10_000 });
		const weekday = new Intl.DateTimeFormat('en-US', { weekday: 'long', timeZone: 'UTC' }).format(
			new Date(noonOnBrowserDay(1))
		);
		await expect(prompt).toContainText(`Did you do ${weekday}'s planned workout early?`);
		await expect(page.getByTestId('plan-link-detail')).toContainText('Long run');

		await page.getByTestId('plan-link-confirm').click();
		await expect(prompt).toBeHidden({ timeout: 10_000 });
		await expect
			.poll(
				async () =>
					(
						await readRow(
							'plan_workouts by id',
							admin.from('plan_workouts').select('completed_run_id').eq('id', workoutId).single()
						)
					).completed_run_id,
				{ timeout: 10_000 }
			)
			.toBe(runId);
	});

	test('"Not this one" moves to the next workout, is remembered, and links nothing', async ({ page }) => {
		await page.goto(`/runs/${runId}`);
		const prompt = page.getByTestId('plan-link-prompt');
		await expect(prompt).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('plan-link-detail')).toContainText('Long run');

		const dismissed = () =>
			page.waitForResponse((r) => r.url().includes('/rpc/dismiss_plan_workout_link') && r.ok());
		await Promise.all([dismissed(), page.getByTestId('plan-link-dismiss').click()]);
		await expect(page.getByTestId('plan-link-detail')).toContainText('Easy');
		await Promise.all([dismissed(), page.getByTestId('plan-link-dismiss').click()]);
		await expect(prompt).toBeHidden();

		// Remembered server-side: the question does not come back.
		await page.reload();
		await expect(page.getByRole('heading', { level: 1 }).first()).toBeVisible({ timeout: 10_000 });
		await expect(prompt).toBeHidden();

		const admin = getAdminClient();
		const rows = await readRows(
			'plan_workouts by id',
			admin.from('plan_workouts').select('completed_run_id').in('id', [workoutId, laterWorkoutId])
		);
		expect(rows.map((r) => r.completed_run_id)).toEqual([null, null]);
	});
});
