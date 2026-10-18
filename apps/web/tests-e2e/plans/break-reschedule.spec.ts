import type { Browser, Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { browserDate, browserDayAt } from '../fixtures/dates';
import { readMaybeRow, readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * A break of a week or more inside an active plan (decisions § 2128): the
 * card on the plan and on Home offers to run the missed weeks again, previews
 * the change, and applies it in one transaction; a race plan keeps its race
 * day by dropping later build weeks, a plan without a race moves its end, and
 * a dismissal is stored server-side so every surface stops offering it.
 *
 * Each test mints its own runner, so no run and no other plan of a seeded
 * user can end or block the break.
 */

const START = -30;
const RACE_PHASES = ['base', 'base', 'build', 'build', 'build', 'build', 'peak', 'peak', 'taper', 'race'] as const;
const FREE_PHASES = ['base', 'base', 'build', 'build', 'build', 'build', 'build', 'build', 'build', 'build'] as const;

/// Ten weeks from 30 days ago: a long run each week's first day (weeks 0 and 1
/// done) and an easy run its fourth; a race plan's race is its last day. Week
/// 1's long run 23 days ago was the last thing done, so the break is 22 days.
async function seedPlan(
	userId: string,
	opts: { race: boolean; name: string; startOffset?: number; status?: 'active' | 'paused' }
): Promise<string> {
	const admin = getAdminClient();
	const start = opts.startOffset ?? START;
	const phases = opts.race ? RACE_PHASES : FREE_PHASES;
	const plan = await readRow(
		'the seeded plan',
		admin
			.from('training_plans')
			.insert({
				user_id: userId,
				name: opts.name,
				goal_event: 'distance_half',
				goal_distance_m: 21097,
				start_date: browserDate(start),
				end_date: browserDate(start + (opts.race ? 63 : 69)),
				days_per_week: 3,
				status: opts.status ?? 'active'
			})
			.select('id')
			.single()
	);
	for (let i = 0; i < phases.length; i++) {
		const week = await readRow(
			`week ${i}`,
			admin
				.from('plan_weeks')
				.insert({ plan_id: plan.id, week_index: i, phase: phases[i], target_volume_m: 18000 })
				.select('id')
				.single()
		);
		const race = phases[i] === 'race';
		const rows: {
			week_id: string;
			scheduled_date: string;
			kind: 'long' | 'race' | 'easy';
			target_distance_m: number;
			manually_completed: boolean;
		}[] = [
			{
				week_id: week.id,
				scheduled_date: browserDate(start + 7 * i),
				kind: race ? 'race' : 'long',
				target_distance_m: race ? 21097 : 12000,
				manually_completed: i <= 1
			}
		];
		if (!race) {
			rows.push({
				week_id: week.id,
				scheduled_date: browserDate(start + 7 * i + 3),
				kind: 'easy',
				target_distance_m: 6000,
				manually_completed: false
			});
		}
		const { error } = await admin.from('plan_workouts').insert(rows);
		if (error) throw error;
	}
	return plan.id;
}

async function phasesOf(planId: string): Promise<string[]> {
	const weeks = await readRows(
		'the plan weeks',
		getAdminClient().from('plan_weeks').select('week_index, phase').eq('plan_id', planId).order('week_index')
	);
	expect(weeks.map((w) => w.week_index)).toEqual(weeks.map((_, i) => i));
	return weeks.map((w) => w.phase);
}

async function planEnd(planId: string): Promise<string> {
	const row = await readRow(
		'the plan',
		getAdminClient().from('training_plans').select('end_date').eq('id', planId).single()
	);
	return row.end_date;
}

async function dismissal(userId: string): Promise<unknown> {
	const row = await readMaybeRow(
		'the runner settings',
		getAdminClient().from('user_settings').select('prefs').eq('user_id', userId).maybeSingle()
	);
	return (row?.prefs as Record<string, unknown> | undefined)?.plan_break_dismissed ?? null;
}

async function openAs(browser: Browser, runner: SagaUser, path: string): Promise<Page> {
	const ctx = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await ctx.newPage();
	await page.goto(path);
	return page;
}

test.describe('picking a plan back up after a break', () => {
	let runner: SagaUser;
	test.beforeEach(async () => {
		[runner] = await createSagaUsers(1, { displayNames: ['Break Runner'] });
	});
	test.afterEach(async () => {
		await deleteSagaUsers([runner]);
	});

	test('repeating this week in a race plan keeps race day and drops a later build week', async ({ browser }) => {
		const planId = await seedPlan(runner.id, { race: true, name: 'e2e break race' });
		const page = await openAs(browser, runner, `/plans/${planId}`);
		const card = page.getByTestId('plan-break-card');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card).toContainText('22 days');

		await card.getByTestId('plan-break-repeat').click();
		const confirm = page.getByTestId('plan-break-confirm');
		await expect(confirm).toContainText('This week runs again next week.');
		await expect(confirm).toContainText('1 later build week is taken out');
		await confirm.getByRole('button', { name: 'Change plan' }).click();
		await expect(page.getByText(/^Plan updated\. It ends /)).toBeVisible();
		await expect(card).toHaveCount(0);

		expect(await phasesOf(planId)).toEqual([
			'base', 'base', 'build', 'build', 'build', 'build', 'peak', 'peak', 'taper', 'race'
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
		const copy = await readRows(
			'the repeated week',
			getAdminClient()
				.from('plan_weeks')
				.select('week_index, plan_workouts(scheduled_date, kind, manually_completed)')
				.eq('plan_id', planId)
				.eq('week_index', 5)
		);
		expect(copy[0].plan_workouts.map((w) => [w.scheduled_date, w.kind, w.manually_completed]).sort()).toEqual([
			[browserDate(START + 35), 'long', false],
			[browserDate(START + 38), 'easy', false]
		]);
		expect(await dismissal(runner.id)).toEqual({ plan_id: planId, from: browserDate(START + 8) });
	});

	test('shortening the build runs the last three weeks again and keeps the taper', async ({ browser }) => {
		const planId = await seedPlan(runner.id, { race: true, name: 'e2e break shorten' });
		const page = await openAs(browser, runner, `/plans/${planId}`);
		const card = page.getByTestId('plan-break-card');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('plan-break-weeks')).toHaveValue('3');
		await expect(card.getByTestId('plan-break-weeks')).toHaveAttribute('max', '3');

		await card.getByRole('button', { name: 'Shorten the build' }).click();
		const confirm = page.getByTestId('plan-break-confirm');
		await expect(confirm).toContainText('The last 3 weeks run again, starting next week.');
		await expect(confirm).toContainText('3 later build weeks are taken out');
		await confirm.getByRole('button', { name: 'Change plan' }).click();
		await expect(page.getByText(/^Plan updated\. It ends /)).toBeVisible();

		expect(await phasesOf(planId)).toEqual([
			'base', 'base', 'build', 'build', 'build', 'build', 'build', 'build', 'taper', 'race'
		]);
		expect(await planEnd(planId)).toBe(browserDate(START + 63));
	});

	test('Home pushes a plan without a race back by the weeks chosen', async ({ browser }) => {
		const planId = await seedPlan(runner.id, { race: false, name: 'e2e break free' });
		const page = await openAs(browser, runner, '/dashboard');
		const card = page.getByTestId('plan-break-card');
		await expect(card).toBeVisible({ timeout: 10_000 });

		await card.getByTestId('plan-break-weeks').fill('2');
		await card.getByRole('button', { name: 'Push the plan back' }).click();
		const confirm = page.getByTestId('plan-break-confirm');
		await expect(confirm).toContainText('The last 2 weeks run again, starting next week.');
		await expect(confirm).toContainText('the plan now ends');
		await confirm.getByRole('button', { name: 'Change plan' }).click();
		await expect(page.getByText(/^Plan updated\. It ends /)).toBeVisible();

		expect(await phasesOf(planId)).toHaveLength(12);
		expect(await planEnd(planId)).toBe(browserDate(START + 69 + 14));
	});

	test('cancelling the preview changes nothing', async ({ browser }) => {
		const planId = await seedPlan(runner.id, { race: true, name: 'e2e break cancel' });
		const page = await openAs(browser, runner, `/plans/${planId}`);
		const card = page.getByTestId('plan-break-card');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await card.getByTestId('plan-break-repeat').click();
		await page.getByTestId('plan-break-confirm').getByRole('button', { name: 'Cancel' }).click();
		await expect(card).toBeVisible();
		expect(await phasesOf(planId)).toEqual([...RACE_PHASES]);
		expect(await dismissal(runner.id)).toBeNull();
	});

	test('keeping the plan as it is stops the offer on every surface', async ({ browser }) => {
		const planId = await seedPlan(runner.id, { race: true, name: 'e2e break keep' });
		const page = await openAs(browser, runner, `/plans/${planId}`);
		const card = page.getByTestId('plan-break-card');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await card.getByTestId('plan-break-dismiss').click();
		await expect(card).toHaveCount(0);
		await expect.poll(() => dismissal(runner.id)).toEqual({ plan_id: planId, from: browserDate(START + 8) });
		expect(await phasesOf(planId)).toEqual([...RACE_PHASES]);

		await page.goto('/dashboard');
		await expect(page.getByText('e2e break keep').first()).toBeVisible({ timeout: 10_000 });
		await page.waitForLoadState('networkidle');
		await expect(page.getByTestId('plan-break-card')).toHaveCount(0);
	});

	test('a run in the last week means there is no break to offer', async ({ browser }) => {
		const planId = await seedPlan(runner.id, { race: true, name: 'e2e break ran' });
		await insertRun({ user_id: runner.id, started_at: browserDayAt(-3, 9), duration_s: 1800, distance_m: 5000 });
		const page = await openAs(browser, runner, `/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: 'e2e break ran' })).toBeVisible({ timeout: 10_000 });
		await page.waitForLoadState('networkidle');
		await expect(page.getByTestId('plan-break-card')).toHaveCount(0);
	});

	test('a paused plan is left to resume', async ({ browser }) => {
		const planId = await seedPlan(runner.id, { race: true, name: 'e2e break paused', status: 'paused' });
		const page = await openAs(browser, runner, `/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: 'e2e break paused' })).toBeVisible({ timeout: 10_000 });
		await page.waitForLoadState('networkidle');
		await expect(page.getByTestId('plan-break-card')).toHaveCount(0);
	});

	test('a later end that runs into the next plan is refused and changes nothing', async ({ browser }) => {
		const planId = await seedPlan(runner.id, { race: false, name: 'e2e break blocked' });
		await seedPlan(runner.id, { race: false, name: 'e2e break next', startOffset: START + 70 });
		const page = await openAs(browser, runner, `/plans/${planId}`);
		const card = page.getByTestId('plan-break-card');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await card.getByTestId('plan-break-repeat').click();
		await page.getByTestId('plan-break-confirm').getByRole('button', { name: 'Change plan' }).click();
		await expect(
			page.getByText('These dates overlap another active training plan. End that plan earlier or pick dates after it.')
		).toBeVisible();
		await expect(card).toBeVisible();
		expect(await phasesOf(planId)).toEqual([...FREE_PHASES]);
		expect(await planEnd(planId)).toBe(browserDate(START + 69));
		expect(await dismissal(runner.id)).toBeNull();
	});
});
