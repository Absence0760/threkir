import { expect, test } from '../fixtures/test';

import { browserDate, noonOnBrowserDay } from '../fixtures/dates';
import { readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deletePlan, deleteRun, insertRun } from '../fixtures/simulate';
import { USER_B } from '../fixtures/users';

/**
 * A completed plan used to end on nothing (issue #1186): the helpers for
 * adherence and distance existed, but no surface assembled them. The plan page
 * now shows a recap of a completed plan — sessions, distance, the race run and
 * its VDOT, records set inside the plan — and a "What's next" that carries the
 * race's 5K equivalent and a start past the recovery into the wizard.
 */
const NAME_PREFIX = 'e2e plan recap';
const RACE_OFFSET = -2;
// A half in 1:05:00: fast enough that no other USER_B run holds the bracket.
const RACE_DISTANCE_M = 21_097.5;
const RACE_SECONDS = 65 * 60;

const planted: { plans: string[]; runs: string[] } = { plans: [], runs: [] };

async function cleanup(): Promise<void> {
	const rows = await readRows(
		'USER_B recap plans',
		getAdminClient().from('training_plans').select('id').eq('user_id', USER_B.id).like('name', `${NAME_PREFIX}%`)
	);
	for (const row of rows) await deletePlan(row.id);
	for (const id of planted.runs.splice(0)) await deleteRun(id);
	planted.plans.length = 0;
}

async function plantCompletedPlan(name: string, status: 'completed' | 'active'): Promise<string> {
	const admin = getAdminClient();
	const raceRunId = await insertRun({
		user_id: USER_B.id,
		started_at: noonOnBrowserDay(RACE_OFFSET),
		duration_s: RACE_SECONDS,
		distance_m: RACE_DISTANCE_M
	});
	planted.runs.push(raceRunId);
	const easyRunId = await insertRun({
		user_id: USER_B.id,
		started_at: noonOnBrowserDay(RACE_OFFSET - 7),
		duration_s: 3600,
		distance_m: 11_000
	});
	planted.runs.push(easyRunId);

	const planId = crypto.randomUUID();
	const weekId = crypto.randomUUID();
	const { error } = await admin.from('training_plans').insert({
		id: planId,
		user_id: USER_B.id,
		name,
		goal_event: 'distance_half',
		goal_distance_m: RACE_DISTANCE_M,
		start_date: browserDate(RACE_OFFSET - 13),
		end_date: browserDate(RACE_OFFSET),
		days_per_week: 3,
		status
	});
	if (error) throw error;
	const { error: weekErr } = await admin
		.from('plan_weeks')
		.insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'race', target_volume_m: 40_000 });
	if (weekErr) throw weekErr;
	const { error: woErr } = await admin.from('plan_workouts').insert([
		{ week_id: weekId, scheduled_date: browserDate(RACE_OFFSET - 7), kind: 'easy', target_distance_m: 10_000, completed_run_id: easyRunId },
		{ week_id: weekId, scheduled_date: browserDate(RACE_OFFSET - 5), kind: 'easy', target_distance_m: 8_000, skipped_at: new Date().toISOString() },
		{ week_id: weekId, scheduled_date: browserDate(RACE_OFFSET - 3), kind: 'easy', target_distance_m: 6_000 },
		{
			week_id: weekId,
			scheduled_date: browserDate(RACE_OFFSET),
			kind: 'race',
			race_name: `${name} race`,
			target_distance_m: RACE_DISTANCE_M,
			completed_run_id: raceRunId
		}
	]);
	if (woErr) throw woErr;
	planted.plans.push(planId);
	return planId;
}

test.describe('the end-of-plan recap', () => {
	test.use({ storageState: USER_B.storageStatePath });
	test.beforeEach(cleanup);
	test.afterEach(cleanup);

	test('a completed plan recaps its block and seeds the next plan', async ({ page }) => {
		const planId = await plantCompletedPlan(`${NAME_PREFIX} done`, 'completed');
		await page.goto(`/plans/${planId}`);

		const recap = page.getByTestId('plan-recap');
		await expect(recap).toBeVisible({ timeout: 10_000 });
		await expect(recap.getByRole('heading', { name: `How ${NAME_PREFIX} done went` })).toBeVisible();
		await expect(recap.getByTestId('plan-recap-sessions')).toContainText('2 of 3');
		await expect(recap.getByTestId('plan-recap-sessions')).toContainText('67% done');
		await expect(recap.getByTestId('plan-recap-sessions')).toContainText('1 skipped');
		await expect(recap.getByTestId('plan-recap-volume')).toContainText('Distance');
		await expect(recap.getByTestId('plan-recap-race')).toContainText(`${NAME_PREFIX} done race`);
		await expect(recap.getByTestId('plan-recap-race')).toContainText('1:05:00');
		await expect(recap.getByTestId('plan-recap-race')).toContainText(/VDOT \d+\.\d/);
		await expect(recap.getByTestId('plan-recap-records')).toContainText('Half marathon', { timeout: 10_000 });
		await expect(recap.getByTestId('plan-recap-recovery')).toContainText('7 easy days');

		const cta = recap.getByTestId('plan-recap-next-plan');
		const href = await cta.getAttribute('href');
		const url = new URL(href ?? '', 'http://x');
		const start = url.searchParams.get('start');
		const seed = Number(url.searchParams.get('recent5k'));
		expect(url.pathname).toBe('/plans/new');
		expect(start).toMatch(/^\d{4}-\d{2}-\d{2}$/);
		expect(start! > browserDate(RACE_OFFSET + 7)).toBe(true);
		expect(seed).toBeGreaterThanOrEqual(12 * 60);

		await cta.click();
		const fieldset = page.locator('fieldset', { hasText: 'Recent 5K time' });
		await expect(fieldset).toBeVisible({ timeout: 10_000 });
		const [minutes, seconds] = await fieldset.locator('input[type="number"]').all();
		await expect(minutes).toHaveValue(String(Math.floor(seed / 60)));
		await expect(seconds).toHaveValue(String(seed % 60));
		await expect(page.locator('input[type="date"]').first()).toHaveValue(start!);
	});

	test('a plan that is not completed shows no recap', async ({ page }) => {
		const planId = await plantCompletedPlan(`${NAME_PREFIX} active`, 'active');
		await page.goto(`/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: `${NAME_PREFIX} active` })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByTestId('finish-plan-prompt')).toBeVisible();
		await expect(page.getByTestId('plan-recap')).toHaveCount(0);
	});
});
