import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * Effort and heart-rate targets on a planned workout, and "updated by your
 * coach" (issue #1186, decisions § 2092). USER_B coaches USER_C_PRO, who has
 * health-data consent in the seed, so the coach may set a bpm cap; the bpm
 * fields are behind the server's hr_prescription gate, which seed.sql opens.
 * The athlete then sees both targets and the provenance line on the workout.
 */
test.describe('workout effort + heart-rate targets', () => {
	test.use({ storageState: USER_B.storageStatePath });

	const admin = getAdminClient();
	let planId: string;
	let tempoId: string;

	test.beforeEach(async () => {
		await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
		await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
		planId = crypto.randomUUID();
		tempoId = crypto.randomUUID();
		const weekId = crypto.randomUUID();
		const { error: planErr } = await admin.from('training_plans').insert({
			id: planId,
			user_id: USER_C_PRO.id,
			name: 'e2e effort targets',
			goal_event: 'distance_10k',
			goal_distance_m: 10_000,
			start_date: browserDate(0),
			end_date: browserDate(6),
			status: 'completed',
			days_per_week: 3
		});
		expect(planErr).toBeNull();
		expect(
			(await admin.from('plan_weeks').insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 7_000 })).error
		).toBeNull();
		expect(
			(
				await admin.from('plan_workouts').insert({
					id: tempoId,
					week_id: weekId,
					scheduled_date: browserDate(1),
					kind: 'tempo',
					target_distance_m: 7_000
				})
			).error
		).toBeNull();
		expect(
			(
				await admin.from('coach_athletes').insert({
					coach_id: USER_B.id,
					athlete_id: USER_C_PRO.id,
					status: 'active',
					invite_token: 'e2eefforttargets000000000000001',
					accepted_at: new Date().toISOString()
				})
			).error
		).toBeNull();
	});

	test.afterEach(async () => {
		await admin.from('training_plans').delete().eq('id', planId);
		await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
		await admin.from('notifications').delete().eq('plan_id', planId);
	});

	test('the coach prescribes Effort 3–4/10 under a 125 bpm cap and the athlete sees it as the coach\'s', async ({
		page,
		browser
	}) => {
		await page.goto(`/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: 'e2e effort targets' })).toBeVisible({
			timeout: 10_000
		});
		await page.locator('.day-link', { hasText: 'Tempo' }).first().click();

		await page.getByLabel('Effort from (1–10)').fill('5');
		await page.getByLabel('Effort up to (1–10)').fill('4');
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.getByText("The first number can't be higher than the second.")).toBeVisible();

		await page.getByLabel('Effort from (1–10)').fill('3');
		await page.getByLabel('Heart rate up to (bpm)').fill('125');
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.getByLabel('Effort up to (1–10)')).toHaveCount(0, { timeout: 10_000 });

		await expect
			.poll(async () => {
				const { data } = await admin
					.from('plan_workouts')
					.select('target_rpe_min, target_rpe_max, target_hr_min_bpm, target_hr_max_bpm, updated_by')
					.eq('id', tempoId)
					.single();
				return data;
			})
			.toEqual({
				target_rpe_min: 3,
				target_rpe_max: 4,
				target_hr_min_bpm: null,
				target_hr_max_bpm: 125,
				updated_by: USER_B.id
			});

		const ctx = await browser.newContext({ storageState: USER_C_PRO.storageStatePath });
		try {
			const athlete = await ctx.newPage();
			await athlete.goto(`/plans/${planId}/workouts/${tempoId}`);
			await expect(athlete.getByTestId('workout-rpe-target')).toContainText('Effort 3–4/10', { timeout: 10_000 });
			await expect(athlete.getByTestId('workout-hr-target')).toContainText('Cap 125 bpm');
			await expect(athlete.getByTestId('workout-coach-edited')).toContainText('Updated by your coach');
		} finally {
			await ctx.close();
		}
	});

	test('the coach does not see their own edit labelled as the coach\'s', async ({ page }) => {
		await page.goto(`/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: 'e2e effort targets' })).toBeVisible({
			timeout: 10_000
		});
		await page.locator('.day-link', { hasText: 'Tempo' }).first().click();
		await page.getByLabel('Effort up to (1–10)').fill('6');
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.getByLabel('Effort up to (1–10)')).toHaveCount(0, { timeout: 10_000 });

		await page.goto(`/plans/${planId}/workouts/${tempoId}`);
		await expect(page.getByTestId('workout-rpe-target')).toContainText('Effort up to 6/10', { timeout: 10_000 });
		await expect(page.getByTestId('workout-coach-edited')).toHaveCount(0);
	});
});
