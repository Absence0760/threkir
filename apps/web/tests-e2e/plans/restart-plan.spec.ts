import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import type { Page } from '@playwright/test';

/**
 * "Restart this plan": a fresh active copy on a new start date, with the plans
 * it replaces retired as abandoned and their history kept. Runs as saga users
 * because the restart retires every active plan its window overlaps, which
 * would reach into other specs' plans on a shared seeded user.
 */

const PLAN_NAME = 'e2e restart block';
const QUEUED_NAME = 'e2e restart queued';
const RPC = '**/rest/v1/rpc/restart_training_plan';

/// The confirm's date format: `formatDateShort` in the en-GB locale and UTC
/// zone playwright.config.ts pins every browser context to.
function shortDate(iso: string): string {
	return new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(
		new Date(`${iso}T00:00:00Z`)
	);
}

async function seedPlan(
	userId: string,
	opts: { status?: string; raceOffset?: number } = {}
): Promise<{ planId: string; doneId: string }> {
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
				status: opts.status ?? 'active'
			})
			.select('id')
			.single()
	);
	let doneId = '';
	const weekIds: string[] = [];
	for (let i = 0; i < 3; i++) {
		const week = await readRow(
			`week ${i}`,
			admin
				.from('plan_weeks')
				.insert({ plan_id: plan.id, week_index: i, phase: 'base', target_volume_m: 5000 })
				.select('id')
				.single()
		);
		weekIds.push(week.id);
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
	const raceOffset = opts.raceOffset ?? -12;
	await addRace(weekIds[raceOffset < 0 ? 0 : 2], raceOffset);
	return { planId: plan.id, doneId };
}

async function addRace(weekId: string, offset: number): Promise<void> {
	const { error } = await getAdminClient().from('plan_workouts').insert({
		week_id: weekId,
		scheduled_date: browserDate(offset),
		kind: 'race',
		target_distance_m: 5000,
		race_name: 'Tune-up',
		race_priority: 'C'
	});
	if (error) throw error;
}

async function openRestart(page: Page, planId: string): Promise<void> {
	await page.goto(`/plans/${planId}`);
	await expect(page.getByRole('heading', { level: 1, name: PLAN_NAME })).toBeVisible({ timeout: 10_000 });
	await page.getByRole('button', { name: 'Adjust plan' }).first().click();
	await page.getByTestId('restart-plan-btn').click();
	await expect(page.getByTestId('restart-plan-dialog')).toBeVisible();
}

async function confirmAndOpenCopy(page: Page, planId: string): Promise<string> {
	await page.getByTestId('restart-confirm').click();
	await expect(page.getByText('Plan restarted. This is your new copy.')).toBeVisible();
	await page.waitForURL((url) => /\/plans\/[0-9a-f-]{36}$/.test(url.pathname) && !url.pathname.endsWith(planId));
	const newId = page.url().split('/plans/')[1];
	await expect(page.getByRole('heading', { level: 1, name: PLAN_NAME })).toBeVisible();
	return newId;
}

async function statusOf(planId: string): Promise<string> {
	const row = await readRow(
		'a plan status',
		getAdminClient().from('training_plans').select('status').eq('id', planId).single()
	);
	return row.status;
}

test.describe('restarting a plan', () => {
	let users: SagaUser[] = [];

	test.beforeAll(async () => {
		users = await createSagaUsers(5);
	});

	test.afterAll(async () => {
		await deleteSagaUsers(users);
	});

	test('an active plan restarts fresh on the picked date; it and an overlapping plan are abandoned', async ({
		browser
	}) => {
		const user = users[0];
		const { planId, doneId } = await seedPlan(user.id);
		const admin = getAdminClient();
		const queued = await readRow(
			'the queued plan',
			admin
				.from('training_plans')
				.insert({
					user_id: user.id,
					name: QUEUED_NAME,
					goal_event: 'distance_5k',
					goal_distance_m: 5000,
					start_date: browserDate(20),
					end_date: browserDate(40),
					days_per_week: 3,
					status: 'active'
				})
				.select('id')
				.single()
		);
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		await openRestart(page, planId);

		const dialog = page.getByTestId('restart-plan-dialog');
		await expect(dialog.getByTestId('restart-start-date')).toHaveValue(browserDate(7));
		await dialog.getByTestId('restart-start-date').fill(browserDate(10));
		await expect(dialog.getByTestId('restart-start-date')).toHaveValue(browserDate(14));
		await expect(dialog.getByTestId('restart-confirm-message')).toHaveText(
			`The new copy starts on ${shortDate(browserDate(14))} and ends on ${shortDate(browserDate(34))}. ` +
				'This plan, and any active plan those dates overlap, is retired as abandoned. ' +
				'Its weeks, workouts and run links are kept. ' +
				`Race day moves to ${shortDate(browserDate(16))}.`
		);

		const newId = await confirmAndOpenCopy(page, planId);

		expect(await statusOf(planId)).toBe('abandoned');
		expect(await statusOf(queued.id)).toBe('abandoned');
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

		await page.goto('/plans');
		const filterRow = page.getByRole('group', { name: /Filter plans by status/ });
		await filterRow.getByRole('button', { name: /^Abandoned\b/ }).click();
		await expect(page.getByRole('heading', { name: QUEUED_NAME })).toBeVisible();
		await expect(page.getByRole('heading', { name: PLAN_NAME })).toBeVisible();
		await filterRow.getByRole('button', { name: /^Active\b/ }).click();
		await expect(page.getByRole('heading', { name: PLAN_NAME })).toBeVisible();
		await expect(page.getByRole('heading', { name: QUEUED_NAME })).toHaveCount(0);
		await ctx.close();
	});

	test('a paused plan restarts and is retired as abandoned', async ({ browser }) => {
		const user = users[1];
		const { planId } = await seedPlan(user.id, { status: 'paused' });
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		await openRestart(page, planId);
		await expect(page.getByTestId('restart-confirm-message')).toContainText(
			'This plan, and any active plan those dates overlap, is retired as abandoned.'
		);
		const newId = await confirmAndOpenCopy(page, planId);
		expect(await statusOf(planId)).toBe('abandoned');
		expect(await statusOf(newId)).toBe('active');
		await ctx.close();
	});

	test('a completed plan restarts and stays completed', async ({ browser }) => {
		const user = users[2];
		const { planId } = await seedPlan(user.id, { status: 'completed' });
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		await openRestart(page, planId);
		await expect(page.getByTestId('restart-confirm-message')).toHaveText(
			`The new copy starts on ${shortDate(browserDate(7))} and ends on ${shortDate(browserDate(27))}. ` +
				'Any active plan those dates overlap is retired as abandoned. ' +
				'This plan keeps its weeks, workouts and run links. ' +
				`Race day moves to ${shortDate(browserDate(9))}.`
		);
		const newId = await confirmAndOpenCopy(page, planId);
		expect(await statusOf(planId)).toBe('completed');
		expect(await statusOf(newId)).toBe('active');
		await ctx.close();
	});

	test('a plan whose race is still ahead is not offered a confirm', async ({ browser }) => {
		const user = users[3];
		const { planId } = await seedPlan(user.id, { raceOffset: 5 });
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		await openRestart(page, planId);
		const dialog = page.getByTestId('restart-plan-dialog');
		await expect(dialog.getByTestId('restart-race-ahead')).toHaveText(
			`This plan's race on ${shortDate(browserDate(5))} is still ahead. Restarting would move race day, ` +
				'so change the race date or start a new plan instead.'
		);
		await expect(dialog.getByTestId('restart-confirm')).toHaveCount(0);
		expect(await statusOf(planId)).toBe('active');
		await ctx.close();
	});

	test('a race added ahead after the dialog opened is refused by the server', async ({ browser }) => {
		const user = users[4];
		const { planId } = await seedPlan(user.id);
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		await openRestart(page, planId);
		const week = await readRow(
			'the last week',
			getAdminClient().from('plan_weeks').select('id').eq('plan_id', planId).eq('week_index', 2).single()
		);
		await addRace(week.id, 5);

		await page.getByTestId('restart-confirm').click();
		await expect(page.getByText("This plan has a race still ahead, so it can't be restarted.")).toBeVisible();
		await expect(page).toHaveURL(new RegExp(`/plans/${planId}$`));
		expect(await statusOf(planId)).toBe('active');
		await ctx.close();
	});

	test('a start the server puts before today gets its own message', async ({ browser, mockRoute }) => {
		const user = users[3];
		const { planId } = await seedPlan(user.id, { status: 'completed' });
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		await mockRoute(page, RPC, (route) =>
			route.fulfill({
				status: 400,
				contentType: 'application/json',
				body: JSON.stringify({
					code: 'RR002',
					message: 'restart_training_plan: the new start date is before today',
					details: null,
					hint: null
				})
			})
		);
		await openRestart(page, planId);
		await page.getByTestId('restart-confirm').click();
		await expect(
			page.getByText("That start date is before today where your account's time zone is set. Pick a later date.")
		).toBeVisible();
		await ctx.close();
	});

	test('a spent hourly budget reads as a wait, not a raw error', async ({ browser, mockRoute }) => {
		const user = users[3];
		const { planId } = await seedPlan(user.id, { status: 'completed' });
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		await mockRoute(page, RPC, (route) =>
			route.fulfill({
				status: 400,
				contentType: 'application/json',
				body: JSON.stringify({
					code: 'P0001',
					message: 'rate limit exceeded for restart_training_plan, retry in 1800s',
					details: null,
					hint: null
				})
			})
		);
		await openRestart(page, planId);
		await page.getByTestId('restart-confirm').click();
		await expect(
			page.getByText("You're restarting plans too quickly — please wait 30 minutes and try again.")
		).toBeVisible();
		await ctx.close();
	});
});
