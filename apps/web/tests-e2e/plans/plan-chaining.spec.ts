import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { deletePlan } from '../fixtures/simulate';
import { USER_B } from '../fixtures/users';

/**
 * Plan chaining (decisions § 2008): several plans may be active as long as
 * their windows do not overlap. A new plan that misses every active plan is
 * created with no replace dialog and queues as "upcoming"; one that overlaps
 * asks first and can end the old plan the day before it starts.
 *
 * Runs as USER_B with a planted active plan, so USER_A's seeded "Richmond
 * Half 2026" — which other specs need active and untrimmed — is never touched.
 * Every USER_B plan this file makes is deleted afterwards.
 */

const BASE_NAME = 'e2e chain base';

/// The wizard snaps its start date to a Sunday, so the spec picks one itself
/// and the date it asserts is the date the plan actually starts on.
function sundayOnOrAfter(offsetDays: number): string {
	const d = new Date(browserDate(offsetDays) + 'T00:00:00Z');
	d.setUTCDate(d.getUTCDate() + ((7 - d.getUTCDay()) % 7));
	return d.toISOString().slice(0, 10);
}

function dayBefore(iso: string): string {
	const d = new Date(iso + 'T00:00:00Z');
	d.setUTCDate(d.getUTCDate() - 1);
	return d.toISOString().slice(0, 10);
}

async function deleteUserBPlans(): Promise<void> {
	const { data } = await getAdminClient()
		.from('training_plans')
		.select('id')
		.eq('user_id', USER_B.id)
		.like('name', 'e2e chain%');
	for (const row of data ?? []) await deletePlan(row.id);
}

async function plantBasePlan(endOffsetDays: number): Promise<{ planId: string; weekId: string; lateWorkoutDate: string }> {
	const admin = getAdminClient();
	const planId = crypto.randomUUID();
	const weekId = crypto.randomUUID();
	const lateWorkoutDate = browserDate(endOffsetDays - 2);
	const { error: planErr } = await admin.from('training_plans').insert({
		id: planId,
		user_id: USER_B.id,
		name: BASE_NAME,
		goal_event: 'distance_half',
		goal_distance_m: 21097,
		start_date: browserDate(-7),
		end_date: browserDate(endOffsetDays),
		days_per_week: 4,
		status: 'active'
	});
	if (planErr) throw planErr;
	const { error: weekErr } = await admin
		.from('plan_weeks')
		.insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 30_000 });
	if (weekErr) throw weekErr;
	const { error: woErr } = await admin.from('plan_workouts').insert([
		{ week_id: weekId, scheduled_date: browserDate(0), kind: 'easy', target_distance_m: 6_000 },
		{ week_id: weekId, scheduled_date: lateWorkoutDate, kind: 'easy', target_distance_m: 6_000 }
	]);
	if (woErr) throw woErr;
	return { planId, weekId, lateWorkoutDate };
}

async function openWizardAndSubmit(page: import('@playwright/test').Page, name: string, startIso: string) {
	await page.goto('/plans');
	await expect(page.locator('.card', { hasText: BASE_NAME })).toBeVisible({ timeout: 10_000 });
	await page.getByRole('button', { name: /New plan/ }).first().click();
	const modal = page.locator('.modal');
	await expect(modal).toBeVisible({ timeout: 5_000 });
	await modal.getByPlaceholder('Autumn half marathon').fill(name);
	await modal.locator('input[type="date"]').first().fill(startIso);
	const submit = modal.getByRole('button', { name: /Create plan/ });
	await expect(submit).toBeEnabled({ timeout: 5_000 });
	await submit.click();
}

test.describe('plan chaining', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.beforeEach(deleteUserBPlans);
	test.afterEach(deleteUserBPlans);

	test('a plan after the active one is created with no replace dialog and queues as upcoming', async ({
		page
	}) => {
		await plantBasePlan(20);
		const name = 'e2e chain next';
		await openWizardAndSubmit(page, name, sundayOnOrAfter(28));

		await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
		await expect(page.getByTestId('plan-overlap-dialog')).toHaveCount(0);

		await page.goto('/plans');
		const base = page.locator('.card', { hasText: BASE_NAME });
		const next = page.locator('.card', { hasText: name });
		await expect(base.locator('.badge.status-active')).toBeVisible({ timeout: 10_000 });
		await expect(next.locator('.badge.status-upcoming')).toBeVisible();
		await expect(next.locator('.badge')).toContainText(/upcoming/i);

		const { data } = await getAdminClient()
			.from('training_plans')
			.select('name, status')
			.eq('user_id', USER_B.id)
			.eq('status', 'active');
		expect((data ?? []).map((p) => p.name).sort()).toEqual([BASE_NAME, name].sort());
	});

	test('an overlapping plan asks first, and ending the old plan early trims it to the day before', async ({
		page
	}) => {
		const { planId, weekId, lateWorkoutDate } = await plantBasePlan(60);
		const start = sundayOnOrAfter(14);
		const trimTo = dayBefore(start);
		await openWizardAndSubmit(page, 'e2e chain overlap', start);

		const dialog = page.getByTestId('plan-overlap-dialog');
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await expect(dialog).toContainText(BASE_NAME);
		await dialog.getByRole('button', { name: new RegExp(`^End .*${BASE_NAME}`) }).click();

		await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });

		const admin = getAdminClient();
		const { data: base } = await admin
			.from('training_plans')
			.select('status, end_date')
			.eq('id', planId)
			.single();
		expect(base).toEqual({ status: 'active', end_date: trimTo });

		const { data: left } = await admin
			.from('plan_workouts')
			.select('scheduled_date')
			.eq('week_id', weekId);
		const dates = (left ?? []).map((w) => w.scheduled_date);
		expect(dates).toContain(browserDate(0));
		expect(dates).not.toContain(lateWorkoutDate);
	});
});
