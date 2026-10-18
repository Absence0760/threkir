import type { Browser, Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * "Too hard? Repeat this week" (decisions § 2156): a walk-run plan offers it
 * above the weeks, and every plan offers it on this week's and last week's
 * row. The preview names the new end date, or the race day a race plan keeps;
 * applying it copies the week in after this one and pushes the rest back one
 * week in one transaction. Cancelling writes nothing.
 *
 * Each test mints its own runner, so the repeat_plan_week budget it spends
 * and the active plan it seeds are its own. Everything up to two days ago is
 * done, so the break offer (§ 2128) stays out of the way.
 */

const START = -30;
const WALK_DAYS = [0, 2, 4];

async function seedWalkRun(userId: string): Promise<string> {
	const admin = getAdminClient();
	const plan = await readRow(
		'the seeded walk-run plan',
		admin
			.from('training_plans')
			.insert({
				user_id: userId,
				name: 'e2e repeat walk-run',
				goal_event: 'distance_5k',
				goal_distance_m: 5000,
				start_date: browserDate(START),
				end_date: browserDate(START + 62),
				days_per_week: 3,
				status: 'active'
			})
			.select('id')
			.single()
	);
	for (let i = 0; i < 9; i++) {
		const week = await readRow(
			`week ${i}`,
			admin
				.from('plan_weeks')
				.insert({ plan_id: plan.id, week_index: i, phase: 'base', target_volume_m: 6000 })
				.select('id')
				.single()
		);
		const { error } = await admin.from('plan_workouts').insert(
			WALK_DAYS.map((d) => ({
				week_id: week.id,
				scheduled_date: browserDate(START + 7 * i + d),
				kind: 'walk_run' as const,
				target_distance_m: 2000,
				target_duration_seconds: 1800,
				manually_completed: START + 7 * i + d <= -2
			}))
		);
		if (error) throw error;
	}
	return plan.id;
}

const RACE_PHASES = ['base', 'base', 'build', 'build', 'build', 'build', 'peak', 'peak', 'taper', 'race'] as const;

async function seedRacePlan(userId: string): Promise<string> {
	const admin = getAdminClient();
	const plan = await readRow(
		'the seeded race plan',
		admin
			.from('training_plans')
			.insert({
				user_id: userId,
				name: 'e2e repeat race',
				goal_event: 'distance_half',
				goal_distance_m: 21097,
				start_date: browserDate(START),
				end_date: browserDate(START + 63),
				days_per_week: 3,
				status: 'active'
			})
			.select('id')
			.single()
	);
	for (let i = 0; i < RACE_PHASES.length; i++) {
		const week = await readRow(
			`week ${i}`,
			admin
				.from('plan_weeks')
				.insert({ plan_id: plan.id, week_index: i, phase: RACE_PHASES[i], target_volume_m: 18000 })
				.select('id')
				.single()
		);
		const race = RACE_PHASES[i] === 'race';
		const rows: {
			week_id: string;
			scheduled_date: string;
			kind: 'long' | 'race' | 'easy';
			target_distance_m: number;
			manually_completed: boolean;
		}[] = [
			{
				week_id: week.id,
				scheduled_date: browserDate(START + 7 * i),
				kind: race ? 'race' : 'long',
				target_distance_m: race ? 21097 : 12000,
				manually_completed: START + 7 * i <= -2
			}
		];
		if (!race) {
			rows.push({
				week_id: week.id,
				scheduled_date: browserDate(START + 7 * i + 3),
				kind: 'easy',
				target_distance_m: 6000,
				manually_completed: START + 7 * i + 3 <= -2
			});
		}
		const { error } = await admin.from('plan_workouts').insert(rows);
		if (error) throw error;
	}
	return plan.id;
}

async function weeksOf(planId: string) {
	return readRows(
		'the plan weeks',
		getAdminClient()
			.from('plan_weeks')
			.select('week_index, phase, plan_workouts(scheduled_date, kind, manually_completed)')
			.eq('plan_id', planId)
			.order('week_index')
	);
}

async function planEnd(planId: string): Promise<string> {
	const row = await readRow(
		'the plan',
		getAdminClient().from('training_plans').select('end_date').eq('id', planId).single()
	);
	return row.end_date;
}

async function openAs(browser: Browser, runner: SagaUser, planId: string): Promise<Page> {
	const ctx = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await ctx.newPage();
	await page.goto(`/plans/${planId}`);
	return page;
}

test.describe('repeating a plan week', () => {
	let runner: SagaUser;
	test.beforeEach(async () => {
		[runner] = await createSagaUsers(1, { displayNames: ['Repeat Runner'] });
	});
	test.afterEach(async () => {
		await deleteSagaUsers([runner]);
	});

	test('a walk-run plan offers this week again and ends a week later', async ({ browser }) => {
		const planId = await seedWalkRun(runner.id);
		const page = await openAs(browser, runner, planId);
		const offer = page.getByTestId('repeat-week-offer');
		await expect(offer).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('plan-break-card')).toHaveCount(0);

		await offer.getByRole('button', { name: 'Repeat this week' }).click();
		const dialog = page.getByTestId('bulk-confirm-dialog');
		await expect(dialog).toContainText('Repeat week 5?');
		await expect(dialog).toContainText('Week 5 runs again as week 6');
		await expect(dialog).toContainText('the plan now ends on');
		await dialog.getByRole('button', { name: 'Repeat week' }).click();
		await expect(page.getByText(/^Week 5 runs again from /)).toBeVisible();

		expect(await planEnd(planId)).toBe(browserDate(START + 69));
		const weeks = await weeksOf(planId);
		expect(weeks.map((w) => w.week_index)).toEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
		expect(weeks[5].plan_workouts.map((w) => [w.scheduled_date, w.kind, w.manually_completed]).sort()).toEqual(
			WALK_DAYS.map((d) => [browserDate(START + 35 + d), 'walk_run', false])
		);
		expect(weeks[9].plan_workouts.map((w) => w.scheduled_date).sort()).toEqual(
			WALK_DAYS.map((d) => browserDate(START + 63 + d))
		);
	});

	test('a race plan repeats last week and keeps race day; cancelling first writes nothing', async ({ browser }) => {
		const planId = await seedRacePlan(runner.id);
		const page = await openAs(browser, runner, planId);
		await expect(page.getByRole('heading', { level: 1, name: 'e2e repeat race' })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('repeat-week-offer')).toHaveCount(0);

		const lastWeek = page.locator('article.week').nth(3);
		await expect(page.locator('article.week').nth(2).getByTestId('repeat-week-btn')).toHaveCount(0);
		await lastWeek.getByTestId('repeat-week-btn').click();
		const dialog = page.getByTestId('bulk-confirm-dialog');
		await expect(dialog).toContainText('Week 4 runs again as week 6');
		await expect(dialog).toContainText('one later week before the taper comes out');
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(dialog).toBeHidden();
		expect((await weeksOf(planId)).map((w) => w.phase)).toEqual([...RACE_PHASES]);

		await lastWeek.getByTestId('repeat-week-btn').click();
		await dialog.getByRole('button', { name: 'Repeat week' }).click();
		await expect(page.getByText(/^Week 4 runs again from /)).toBeVisible();

		const weeks = await weeksOf(planId);
		expect(weeks.map((w) => w.phase)).toEqual([...RACE_PHASES]);
		expect(weeks[5].plan_workouts.map((w) => [w.scheduled_date, w.kind, w.manually_completed]).sort()).toEqual([
			[browserDate(START + 35), 'long', false],
			[browserDate(START + 38), 'easy', false]
		]);
		expect(await planEnd(planId)).toBe(browserDate(START + 63));
		const race = await readRow(
			'the race',
			getAdminClient()
				.from('plan_workouts')
				.select('scheduled_date, plan_weeks!inner(plan_id)')
				.eq('plan_weeks.plan_id', planId)
				.eq('kind', 'race')
				.single()
		);
		expect(race.scheduled_date).toBe(browserDate(START + 63));
	});
});
