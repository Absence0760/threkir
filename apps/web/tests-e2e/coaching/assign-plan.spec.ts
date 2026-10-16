import { expect, test } from '../fixtures/test';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_B, USER_C_PRO } from '../fixtures/users';
import { readMaybeRow } from '../fixtures/db-read';
import { browserDate } from '../fixtures/dates';

// USER_B (alex) is the coach; USER_C_PRO (morgan) is the linked athlete.
const INVITE_TOKEN = 'e2eassignplantoken00000000000001';
const SOURCE_PLAN_NAME = 'E2E Assign Source Plan';

async function clean() {
	const admin = getAdminClient();
	await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
	await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
	// These two fixtures carry no seeded plans; clear any a test created so
	// the "athlete has no active plan" precondition holds.
	await admin.from('training_plans').delete().eq('user_id', USER_C_PRO.id);
	await admin.from('training_plans').delete().eq('user_id', USER_B.id);
}

test.describe('/coaching/athletes/[id] — assign a plan', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.beforeEach(async () => {
		await clean();
		const admin = getAdminClient();
		await admin.from('coach_athletes').insert({
			coach_id: USER_B.id,
			athlete_id: USER_C_PRO.id,
			status: 'active',
			invite_token: INVITE_TOKEN,
			accepted_at: new Date().toISOString()
		});
		// The coach owns a (completed) plan they can clone to the athlete.
		await admin.from('training_plans').insert({
			user_id: USER_B.id,
			name: SOURCE_PLAN_NAME,
			goal_event: 'distance_10k',
			goal_distance_m: 10000,
			start_date: '2026-06-01',
			end_date: '2026-07-01',
			status: 'completed'
		});
	});

	test.afterEach(clean);

	test('coach assigns one of their plans; it becomes the athlete active plan', async ({ page }) => {
		await page.goto(`/coaching/athletes/${USER_C_PRO.id}`);
		await expect(
			page.getByRole('heading', { level: 3, name: 'Assign a plan' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByLabel('Plan to assign').selectOption({ label: SOURCE_PLAN_NAME });
		await page.getByRole('button', { name: 'Assign plan' }).click();

		// The cloned plan is now the athlete's active plan, badged as ours.
		await expect(page.getByText('Assigned by you')).toBeVisible({ timeout: 10_000 });
		await expect(
			page.getByRole('link', { name: SOURCE_PLAN_NAME })
		).toBeVisible({ timeout: 10_000 });

		// And it really landed in the athlete's account, owned by them.
		const admin = getAdminClient();
		const data = await readMaybeRow(
			'training_plans by user_id+status',
			admin
				.from('training_plans')
				.select('user_id, status, assigned_by_coach_id')
				.eq('user_id', USER_C_PRO.id)
				.eq('status', 'active')
				.maybeSingle()
		);
		expect(data?.assigned_by_coach_id).toBe(USER_B.id);
	});

	test('an athlete with an active plan still gets the form, naming the plan and starting after it', async ({ page }) => {
		await getAdminClient().from('training_plans').insert({
			user_id: USER_C_PRO.id,
			name: 'Athlete own plan',
			goal_event: 'distance_5k',
			goal_distance_m: 5000,
			start_date: browserDate(-5),
			end_date: browserDate(20),
			status: 'active'
		});

		await page.goto(`/coaching/athletes/${USER_C_PRO.id}`);
		await expect(page.getByRole('link', { name: 'Athlete own plan' })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByRole('heading', { level: 3, name: 'Assign a plan' })).toBeVisible();
		await expect(page.getByTestId('assign-blockers')).toContainText('“Athlete own plan” runs until');
		await expect(page.getByLabel('Start date')).toHaveValue(browserDate(21));
		await expect(page.getByText(/already has an active plan/i)).toHaveCount(0);
	});
});
