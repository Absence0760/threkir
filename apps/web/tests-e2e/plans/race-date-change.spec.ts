import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deletePlan } from '../fixtures/simulate';
import { USER_B } from '../fixtures/users';

/**
 * Adjust plan → Change race date: a later race
 * repeats a build week in front of the peak and the taper stays whole; a date
 * too close for the taper is refused with the earliest one the plan can reach,
 * and nothing is written. Runs as USER_B on a paused plan this file seeds and
 * deletes, so it holds no dates against the runner's other plans.
 */

const PLAN_NAME = 'e2e race date block';

async function deletePlans(): Promise<void> {
	const rows = await readRows(
		'USER_B race date plans',
		getAdminClient().from('training_plans').select('id').eq('user_id', USER_B.id).like('name', 'e2e race date%')
	);
	for (const row of rows) await deletePlan(row.id);
}

const PHASES = ['base', 'base', 'build', 'build', 'build', 'peak', 'taper', 'race'] as const;

/// Eight weeks from `startOffset` days from today (by default 14 days ago, so
/// today is in week 2): a long run on each week's first day, the race on the
/// last week's first day and an easy run on each day after it.
async function seedPlan(
	opts: { startOffset?: number; status?: 'active' | 'paused'; name?: string } = {}
): Promise<string> {
	const startOffset = opts.startOffset ?? -14;
	const admin = getAdminClient();
	const plan = await readRow(
		'the seeded plan',
		admin
			.from('training_plans')
			.insert({
				user_id: USER_B.id,
				name: opts.name ?? PLAN_NAME,
				goal_event: 'distance_half',
				goal_distance_m: 21097,
				start_date: browserDate(startOffset),
				end_date: browserDate(startOffset + 55),
				days_per_week: 4,
				status: opts.status ?? 'paused'
			})
			.select('id')
			.single()
	);
	for (let i = 0; i < PHASES.length; i++) {
		const week = await readRow(
			`week ${i}`,
			admin
				.from('plan_weeks')
				.insert({ plan_id: plan.id, week_index: i, phase: PHASES[i], target_volume_m: 20000 })
				.select('id')
				.single()
		);
		const rows: { week_id: string; scheduled_date: string; kind: 'long' | 'race' | 'easy'; target_distance_m: number }[] = [
			{
				week_id: week.id,
				scheduled_date: browserDate(startOffset + 7 * i),
				kind: i === PHASES.length - 1 ? 'race' : 'long',
				target_distance_m: i === PHASES.length - 1 ? 21097 : 14000
			}
		];
		if (i === PHASES.length - 1) {
			for (let d = 1; d <= 6; d++) {
				rows.push({ week_id: week.id, scheduled_date: browserDate(startOffset + 7 * i + d), kind: 'easy', target_distance_m: 5000 });
			}
		}
		const { error } = await admin.from('plan_workouts').insert(rows);
		if (error) throw error;
	}
	return plan.id;
}

async function openChangeRaceDate(page: import('@playwright/test').Page, planId: string, date: string) {
	await page.goto(`/plans/${planId}`);
	await expect(page.getByRole('heading', { level: 1, name: PLAN_NAME })).toBeVisible({ timeout: 10_000 });
	await page.getByRole('button', { name: 'Adjust plan' }).first().click();
	await page.getByTestId('race-date-input').fill(date);
	await page.getByRole('button', { name: 'Change race date' }).click();
}

test.describe('changing a plan race date', () => {
	test.use({ storageState: USER_B.storageStatePath });
	test.beforeEach(deletePlans);
	test.afterEach(deletePlans);

	test('a later race adds build weeks before the peak and keeps the taper', async ({ page }) => {
		const planId = await seedPlan();
		await openChangeRaceDate(page, planId, browserDate(49));

		const dialog = page.getByTestId('bulk-confirm-dialog');
		await expect(dialog).toContainText('2 build weeks are added before the taper');
		await dialog.getByRole('button', { name: 'Apply' }).click();
		await expect(page.getByText(/Race date changed to/)).toBeVisible();

		const admin = getAdminClient();
		const plan = await readRow(
			'the re-anchored plan',
			admin.from('training_plans').select('end_date').eq('id', planId).single()
		);
		expect(plan.end_date).toBe(browserDate(49));
		const weeks = await readRows(
			'its weeks',
			admin.from('plan_weeks').select('week_index, phase').eq('plan_id', planId).order('week_index')
		);
		expect(weeks.map((w) => w.phase)).toEqual([
			'base', 'base', 'build', 'build', 'build', 'build', 'build', 'peak', 'taper', 'race'
		]);
		expect(weeks.map((w) => w.week_index)).toEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
		const race = await readRows(
			'the race',
			admin.from('plan_workouts').select('scheduled_date, plan_weeks!inner(plan_id)').eq('plan_weeks.plan_id', planId).eq('kind', 'race')
		);
		expect(race.map((r) => r.scheduled_date)).toEqual([browserDate(49)]);
	});

	test('a race too close for the taper is refused and nothing changes', async ({ page }) => {
		const planId = await seedPlan();
		await openChangeRaceDate(page, planId, browserDate(4));

		await expect(page.getByText(/too soon to keep your taper/)).toBeVisible();
		await expect(page.getByTestId('bulk-confirm-dialog')).toBeHidden();
		const plan = await readRow(
			'the untouched plan',
			getAdminClient().from('training_plans').select('end_date').eq('id', planId).single()
		);
		expect(plan.end_date).toBe(browserDate(-14 + 55));
	});

	test('an earlier race cuts build weeks, keeps the taper and closes the gap', async ({ page }) => {
		const planId = await seedPlan();
		await openChangeRaceDate(page, planId, browserDate(24));

		const dialog = page.getByTestId('bulk-confirm-dialog');
		await expect(dialog).toContainText('2 build weeks are cut');
		await dialog.getByRole('button', { name: 'Apply' }).click();
		await expect(page.getByText(/Race date changed to/)).toBeVisible();

		const admin = getAdminClient();
		const plan = await readRow(
			'the re-anchored plan',
			admin.from('training_plans').select('end_date').eq('id', planId).single()
		);
		expect(plan.end_date).toBe(browserDate(24));
		const weeks = await readRows(
			'its weeks',
			admin.from('plan_weeks').select('week_index, phase').eq('plan_id', planId).order('week_index')
		);
		expect(weeks.map((w) => w.phase)).toEqual(['base', 'base', 'build', 'peak', 'taper', 'race']);
		expect(weeks.map((w) => w.week_index)).toEqual([0, 1, 2, 3, 4, 5]);
	});

	test('a later race that runs into a queued plan is refused naming it', async ({ page }) => {
		const planId = await seedPlan({ startOffset: 400, status: 'active' });
		await seedPlan({ startOffset: 460, status: 'active', name: 'e2e race date queued' });
		await openChangeRaceDate(page, planId, browserDate(400 + 63));

		await expect(page.getByText(/runs into e2e race date queued/)).toBeVisible();
		await expect(page.getByTestId('bulk-confirm-dialog')).toBeHidden();
		const plan = await readRow(
			'the untouched plan',
			getAdminClient().from('training_plans').select('end_date').eq('id', planId).single()
		);
		expect(plan.end_date).toBe(browserDate(400 + 55));
	});
});
