import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';
import { readMaybeRow } from '../fixtures/db-read';

/**
 * /plans/new built-in starter library (Training P3). The engine
 * (starter_plans.ts) is unit-tested; this pins the picker UI: choosing a
 * starter instantiates it via generatePlan → createTrainingPlan and lands on
 * the new plan's detail. The starter overlaps the seeded plan, so the create asks first and the
 * test chooses Replace, which completes the prior active plan — the test must
 * NOT delete USER_A's plans wholesale (that would destroy the shared seeded
 * `Richmond Half` plan other specs depend on). Cleanup removes only the plan
 * THIS test creates and restores the seed plan to active.
 */

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';
const CREATED_PLAN_NAME = 'Half Marathon — 12 weeks';

async function cleanup() {
	const admin = getAdminClient();
	// Delete the test-created starter FIRST (clears the overlap), then
	// restore the seeded plan to active — never both active at once.
	await admin
		.from('training_plans')
		.delete()
		.eq('user_id', USER_A.id)
		.eq('name', CREATED_PLAN_NAME);
	await admin.from('training_plans').update({ status: 'active' }).eq('id', SEED_PLAN_ID);
}

test.describe('/plans/new starter library', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(cleanup);
	test.afterEach(cleanup);

	test('picking a built-in starter creates a plan and lands on its detail', async ({ page }) => {
		await page.goto('/plans/new');
		await expect(
			page.getByRole('heading', { level: 2, name: 'Start from a built-in plan' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByLabel('Starter plan').selectOption('half_12wk');
		await page
			.locator('.starter-picker')
			.getByRole('button', { name: 'Start this plan' })
			.click();
		// The starter overlaps the seeded plan, so the create asks first
		// (decisions § 2050); Replace completes the seed plan, as before.
		const overlapDialog = page.getByTestId('plan-overlap-dialog');
		await expect(overlapDialog).toBeVisible({ timeout: 10_000 });
		await overlapDialog.getByRole('button', { name: 'Replace plan' }).click();

		await page.waitForURL(/\/plans\/[0-9a-f-]{36}$/, { timeout: 15_000 });

		// The 12-week half-marathon starter persisted as USER_A's active plan.
		const data = await readMaybeRow(
			'training_plans by user_id+status',
			getAdminClient()
				.from('training_plans')
				.select('name, status, goal_event')
				.eq('user_id', USER_A.id)
				.eq('status', 'active')
				.maybeSingle()
		);
		expect(data?.name).toContain('Half Marathon');
		expect(data?.goal_event).toBe('distance_half');
	});
});
