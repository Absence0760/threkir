import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readCount, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * A coach assigning a plan once the athlete can hold several active plans
 * (plan chaining, decisions § 2008). assign_plan_to_athlete refuses only when
 * one of the athlete's active plans shares a day with the assigned window; a
 * plan queued clear of it is neither a reason to refuse nor something the
 * assignment touches.
 *
 * The form stays offered while the athlete holds plans: it names them and
 * starts the date picker after them, and the server decides. The refusal case
 * plants the athlete's plans AFTER the page has loaded — the athlete starting
 * a plan while the coach is choosing one — since the picker otherwise starts
 * clear of every plan the page knows about.
 *
 * Runs as two throwaway users, so the seeded coach fixtures are never touched.
 */

const SOURCE_NAME = 'e2e coach source block';
const OVERLAPPING = 'e2e athlete own block';
const QUEUED = 'e2e athlete queued block';

let coach: SagaUser;
let athlete: SagaUser;

test.beforeAll(async () => {
	[coach, athlete] = await createSagaUsers(2, { displayNames: ['Overlap Coach', 'Overlap Athlete'] });
	const admin = getAdminClient();
	const { error: linkErr } = await admin.from('coach_athletes').insert({
		coach_id: coach.id,
		athlete_id: athlete.id,
		status: 'active',
		invite_token: crypto.randomUUID().replaceAll('-', ''),
		accepted_at: new Date().toISOString(),
	});
	if (linkErr) throw linkErr;
	// A 28-day source plan; assigned from today it covers today..today+27.
	await plantPlan(coach.id, SOURCE_NAME, -100, -73, 'completed');
});

test.afterAll(async () => {
	await deleteSagaUsers([coach, athlete].filter(Boolean));
});

test.afterEach(async () => {
	const { error } = await getAdminClient().from('training_plans').delete().eq('user_id', athlete.id);
	if (error) throw error;
});

async function plantPlan(
	userId: string,
	name: string,
	startOffset: number,
	endOffset: number,
	status: 'active' | 'completed' = 'active',
): Promise<string> {
	const admin = getAdminClient();
	const planId = crypto.randomUUID();
	const weekId = crypto.randomUUID();
	const { error: planErr } = await admin.from('training_plans').insert({
		id: planId,
		user_id: userId,
		name,
		goal_event: 'distance_10k',
		goal_distance_m: 10_000,
		start_date: browserDate(startOffset),
		end_date: browserDate(endOffset),
		days_per_week: 4,
		status,
	});
	if (planErr) throw planErr;
	const { error: weekErr } = await admin
		.from('plan_weeks')
		.insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 10_000 });
	if (weekErr) throw weekErr;
	const { error: woErr } = await admin
		.from('plan_workouts')
		.insert({ week_id: weekId, scheduled_date: browserDate(startOffset), kind: 'easy', target_distance_m: 6_000 });
	if (woErr) throw woErr;
	return planId;
}

async function openAssignForm(page: Page, expectedStart = browserDate(0)): Promise<void> {
	await page.goto(`/coaching/athletes/${athlete.id}`);
	await expect(page.getByRole('heading', { level: 3, name: 'Assign a plan' })).toBeVisible({ timeout: 10_000 });
	await page.getByLabel('Plan to assign').selectOption({ label: SOURCE_NAME });
	await expect(page.getByLabel('Start date')).toHaveValue(expectedStart);
}

async function athletePlans(): Promise<{ name: string; status: string; start_date: string; end_date: string; assigned_by_coach_id: string | null }[]> {
	return readRows(
		"the athlete's plans",
		getAdminClient()
			.from('training_plans')
			.select('name, status, start_date, end_date, assigned_by_coach_id')
			.eq('user_id', athlete.id)
			.order('start_date'),
	);
}

test.describe('assigning over an athlete who now holds active plans', () => {
	test.describe.configure({ timeout: 90_000 });

	test('an active plan sharing the assigned dates refuses the assignment and changes nothing', async ({ browser }) => {
		const context = await browser.newContext({ storageState: coach.storageStatePath });
		const page = await context.newPage();
		try {
			await openAssignForm(page);
			await plantPlan(athlete.id, OVERLAPPING, 20, 40);
			await plantPlan(athlete.id, QUEUED, 60, 90);

			await page.getByRole('button', { name: 'Assign plan' }).click();
			const toast = page.locator('.toast.toast-error');
			await expect(toast).toContainText(`Those dates overlap Overlap Athlete's plan “${OVERLAPPING}”`, { timeout: 10_000 });
			await expect(toast).toContainText('Pick a start date after it ends.');
			await expect(page.getByText('Assigned by you')).toHaveCount(0);
			// The re-read plans now guide the next attempt.
			await expect(page.getByTestId('assign-blockers')).toContainText(OVERLAPPING);
			await expect(page.getByTestId('assign-blockers')).toContainText(QUEUED);

			expect(await athletePlans()).toEqual([
				{ name: OVERLAPPING, status: 'active', start_date: browserDate(20), end_date: browserDate(40), assigned_by_coach_id: null },
				{ name: QUEUED, status: 'active', start_date: browserDate(60), end_date: browserDate(90), assigned_by_coach_id: null },
			]);
		} finally {
			await context.close();
		}
	});

	test('a plan queued clear of the assigned dates is left active and unmoved beside the assignment', async ({ browser }) => {
		const context = await browser.newContext({ storageState: coach.storageStatePath });
		const page = await context.newPage();
		try {
			await openAssignForm(page);
			await plantPlan(athlete.id, QUEUED, 60, 90);

			await page.getByRole('button', { name: 'Assign plan' }).click();
			await expect(page.getByText('Assigned by you')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByRole('link', { name: SOURCE_NAME })).toBeVisible();

			expect(await athletePlans()).toEqual([
				{ name: SOURCE_NAME, status: 'active', start_date: browserDate(0), end_date: browserDate(27), assigned_by_coach_id: coach.id },
				{ name: QUEUED, status: 'active', start_date: browserDate(60), end_date: browserDate(90), assigned_by_coach_id: null },
			]);
			expect(
				await readCount(
					"the assigned plan's workouts",
					getAdminClient()
						.from('plan_workouts')
						.select('id, plan_weeks!inner(plan_id, training_plans!inner(user_id, assigned_by_coach_id))', { count: 'exact', head: true })
						.eq('plan_weeks.training_plans.user_id', athlete.id)
						.eq('plan_weeks.training_plans.assigned_by_coach_id', coach.id),
				),
			).toBe(1);
		} finally {
			await context.close();
		}
	});

	test('an athlete with a current and a queued plan still gets the form, which names both and starts after them', async ({ browser }) => {
		await plantPlan(athlete.id, OVERLAPPING, -5, 20);
		await plantPlan(athlete.id, QUEUED, 21, 50);
		const context = await browser.newContext({ storageState: coach.storageStatePath });
		const page = await context.newPage();
		try {
			await openAssignForm(page, browserDate(51));
			const hint = page.getByTestId('assign-blockers');
			await expect(hint).toContainText(`Overlap Athlete's plan “${OVERLAPPING}” runs until`);
			await expect(hint).toContainText(`and “${QUEUED}” runs`);
			await expect(hint).toContainText("A plan you assign can't overlap either of them.");
			await expect(page.getByText(/until they finish or abandon it/)).toHaveCount(0);

			await page.getByRole('button', { name: 'Assign plan' }).click();
			await expect(page.locator('.toast.toast-success')).toContainText('Plan assigned to Overlap Athlete', { timeout: 10_000 });
			expect((await athletePlans()).map((p) => [p.name, p.status, p.start_date])).toEqual([
				[OVERLAPPING, 'active', browserDate(-5)],
				[QUEUED, 'active', browserDate(21)],
				[SOURCE_NAME, 'active', browserDate(51)],
			]);
		} finally {
			await context.close();
		}
	});
});
