import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { deletePlan } from '../fixtures/simulate';
import { USER_B } from '../fixtures/users';

/**
 * Several races per plan (decisions § 2009): a plan imported with a B race
 * mid-block and its A race on the end date lists both, and the countdown and
 * race-week panel target the B race first.
 *
 * Runs as USER_B, so USER_A's seeded "Richmond Half 2026" is never replaced.
 * Every plan this file makes is deleted afterwards.
 */

const PLAN_NAME = 'e2e races block';
const B_RACE = 'Two Oceans e2e';
const A_RACE = 'Comrades e2e';

async function deleteUserBRacePlans(): Promise<void> {
	const { data } = await getAdminClient()
		.from('training_plans')
		.select('id')
		.eq('user_id', USER_B.id)
		.like('name', 'e2e races%');
	for (const row of data ?? []) await deletePlan(row.id);
}

test.describe('races in a plan', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.beforeEach(deleteUserBRacePlans);
	test.afterEach(deleteUserBRacePlans);

	test('an imported B race gets its own countdown before the A race on the end date', async ({ page }) => {
		const bDate = browserDate(10);
		const aDate = browserDate(40);
		const md = [
			`# ${PLAN_NAME}`,
			'- Goal event: custom',
			'- Goal distance: 90.00 km',
			`- Start date: ${browserDate(0)}`,
			'',
			'| Week | Date | Type | Distance | Pace | Notes | Race | Priority | Goal |',
			'| --- | --- | --- | --- | --- | --- | --- | --- | --- |',
			`| 1 | ${browserDate(0)} | easy | 8.00 km | | |  |  |  |`,
			`| 2 | ${bDate} | race | 56.00 km | | | ${B_RACE} | B | 6:30:00 |`,
			`| 5 | ${browserDate(30)} | long | 30.00 km | | |  |  |  |`,
			`| 6 | ${aDate} | race | 90.00 km | | | ${A_RACE} | A |  |`,
		].join('\n');

		await page.goto('/plans/new');
		await expect(page.locator('.week-item').first()).toBeVisible({ timeout: 10_000 });
		await page.getByText('Import a plan', { exact: true }).click();
		await page.getByRole('textbox', { name: 'Import a plan' }).fill(md);
		await page.getByRole('button', { name: 'Load plan' }).click();
		await expect(page.locator('.imported-note')).toBeVisible();

		const submit = page.getByRole('button', { name: /Create plan/ });
		await expect(submit).toBeEnabled({ timeout: 5_000 });
		await submit.click();
		await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });

		const races = page.getByRole('region', { name: 'Races in this plan' });
		await expect(races).toBeVisible({ timeout: 10_000 });
		const items = races.getByRole('listitem');
		await expect(items).toHaveCount(2);
		await expect(items.nth(0)).toContainText(B_RACE);
		await expect(items.nth(0).getByLabel('Priority B')).toBeVisible();
		await expect(items.nth(0)).toContainText('Next');
		await expect(items.nth(1)).toContainText(A_RACE);
		await expect(items.nth(1).getByLabel('Priority A')).toBeVisible();

		await expect(page.locator('.relation-pill')).toHaveText(`${B_RACE} in 10 days`);
		await expect(page.locator('.race-day-panel .kicker')).toHaveText(B_RACE);

		const admin = getAdminClient();
		const { data: plan } = await admin
			.from('training_plans')
			.select('id')
			.eq('user_id', USER_B.id)
			.eq('name', PLAN_NAME)
			.single();
		const { data: weeks } = await admin.from('plan_weeks').select('id').eq('plan_id', plan!.id);
		const { data } = await admin
			.from('plan_workouts')
			.select('scheduled_date, race_name, race_priority, target_duration_seconds')
			.in('week_id', (weeks ?? []).map((w) => w.id))
			.eq('kind', 'race')
			.order('scheduled_date');
		expect((data ?? []).map((w) => [w.scheduled_date, w.race_name, w.race_priority, w.target_duration_seconds])).toEqual([
			[bDate, B_RACE, 'B', 23_400],
			[aDate, A_RACE, 'A', null],
		]);
	});
});
