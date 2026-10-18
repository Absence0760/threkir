import { expect, test } from '../fixtures/test';

import { readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /plans/[id] Abandon. A paused plan used to be abandonable only from
 * the list; detail had no way out. Adjust plan now lists Abandon for an active
 * or paused plan, behind a ConfirmDialog that says what is kept, and the page
 * reflects the new status once it lands. The active plan is seeded well past
 * every seeded plan's window so the one-active-per-window constraint never
 * touches the seed; nobody but the owner is offered it.
 */

const dayMs = 24 * 3600 * 1000;
const iso = (d: Date) => d.toISOString().slice(0, 10);

test.describe('/plans/[id] Abandon', () => {
	test.use({ storageState: USER_A.storageStatePath });

	async function seedPlan(
		name: string,
		status: 'active' | 'paused',
		ownerId: string = USER_A.id
	): Promise<{ planId: string; weekId: string }> {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const weekId = crypto.randomUUID();
		const offset = status === 'active' ? 900 : -7;
		const { error } = await admin.from('training_plans').insert({
			id: planId, user_id: ownerId, name, goal_event: 'distance_10k',
			goal_distance_m: 10_000, goal_time_seconds: null,
			start_date: iso(new Date(Date.now() + offset * dayMs)),
			end_date: iso(new Date(Date.now() + (offset + 56) * dayMs)), status, days_per_week: 4
		});
		expect(error).toBeNull();
		await admin.from('plan_weeks').insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 30_000 });
		await admin.from('plan_workouts').insert({
			week_id: weekId, scheduled_date: iso(new Date(Date.now() + (offset + 2) * dayMs)), kind: 'easy', target_distance_m: 6_000
		});
		return { planId, weekId };
	}

	async function abandonFromDetail(
		page: import('@playwright/test').Page,
		planId: string,
		name: string,
		lifecycle: 'Pause plan' | 'Resume plan'
	): Promise<void> {
		const admin = getAdminClient();
		await page.goto(`/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name })).toBeVisible({ timeout: 10_000 });

		const adjust = page.getByRole('button', { name: 'Adjust plan' });
		const dialog = page.getByTestId('adjust-plan-dialog');
		const confirm = page.getByTestId('abandon-confirm-dialog');
		const status = async () =>
			(await admin.from('training_plans').select('status').eq('id', planId).single()).data?.status;
		const before = await status();

		await adjust.click();
		await expect(dialog.getByRole('button', { name: lifecycle })).toBeVisible();
		const abandon = dialog.getByRole('button', { name: 'Abandon plan' });
		await expect(abandon).toHaveAccessibleDescription(/weeks, workouts and linked runs are kept/);
		await abandon.click();
		await expect(dialog).toBeHidden();
		await expect(confirm).toContainText(`Abandon "${name}"? Its weeks, workouts and linked runs are kept.`);

		await confirm.getByRole('button', { name: 'Cancel' }).click();
		await expect(confirm).toBeHidden();
		expect(await status()).toBe(before);

		await adjust.click();
		await dialog.getByRole('button', { name: 'Abandon plan' }).click();
		await confirm.getByRole('button', { name: 'Abandon' }).click();
		await expect(confirm).toBeHidden();
		await expect.poll(status).toBe('abandoned');

		await adjust.click();
		await expect(dialog).toBeVisible();
		await expect(dialog.getByRole('button', { name: 'Abandon plan' })).toHaveCount(0);
		await expect(dialog.getByRole('button', { name: 'Pause plan' })).toHaveCount(0);
		await expect(dialog.getByRole('button', { name: 'Resume plan' })).toHaveCount(0);
	}

	test('an active plan can be abandoned from detail, and the page reflects it', async ({ page }) => {
		const admin = getAdminClient();
		const { planId, weekId } = await seedPlan('e2e abandon active', 'active');
		try {
			await abandonFromDetail(page, planId, 'e2e abandon active', 'Pause plan');
			const kept = await readRows(
				'abandoned plan workouts',
				admin.from('plan_workouts').select('id').eq('week_id', weekId)
			);
			expect(kept).toHaveLength(1);
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});

	test('a paused plan can be abandoned from detail, and the page reflects it', async ({ page }) => {
		const admin = getAdminClient();
		const { planId, weekId } = await seedPlan('e2e abandon paused', 'paused');
		try {
			await abandonFromDetail(page, planId, 'e2e abandon paused', 'Resume plan');
			const kept = await readRows(
				'abandoned plan workouts',
				admin.from('plan_workouts').select('id').eq('week_id', weekId)
			);
			expect(kept).toHaveLength(1);
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});

	test('a failed abandon keeps the dialog open and says so', async ({ page }) => {
		const admin = getAdminClient();
		const { planId } = await seedPlan('e2e abandon fails', 'paused');
		try {
			await page.route('**/rest/v1/training_plans**', async (route) => {
				if (route.request().method() === 'PATCH') {
					await route.fulfill({
						status: 500,
						contentType: 'application/json',
						body: JSON.stringify({ message: 'simulated failure' })
					});
					return;
				}
				await route.fallback();
			});

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e abandon fails' }))
				.toBeVisible({ timeout: 10_000 });
			await page.getByRole('button', { name: 'Adjust plan' }).click();
			await page.getByTestId('adjust-plan-dialog').getByRole('button', { name: 'Abandon plan' }).click();
			const confirm = page.getByTestId('abandon-confirm-dialog');
			await confirm.getByRole('button', { name: 'Abandon' }).click();

			await expect(page.locator('.toast-error')).toBeVisible({ timeout: 5_000 });
			await expect(confirm).toBeVisible();
			expect((await admin.from('training_plans').select('status').eq('id', planId).single()).data)
				.toEqual({ status: 'paused' });
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});
});

test.describe('/plans/[id] Abandon — not the owner', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test("an athlete's coach is offered no abandon on the athlete's plan", async ({ page }) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
		await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
		try {
			const { error } = await admin.from('training_plans').insert({
				id: planId, user_id: USER_C_PRO.id, name: 'e2e abandon not owner', goal_event: 'distance_10k',
				goal_distance_m: 10_000, start_date: iso(new Date(Date.now() + 900 * dayMs)),
				end_date: iso(new Date(Date.now() + 956 * dayMs)), status: 'active', days_per_week: 4
			});
			expect(error).toBeNull();
			const link = await admin.from('coach_athletes').insert({
				coach_id: USER_B.id, athlete_id: USER_C_PRO.id, status: 'active',
				invite_token: 'e2edetailabandonnotowner00000001', accepted_at: new Date().toISOString()
			});
			expect(link.error).toBeNull();

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e abandon not owner' }))
				.toBeVisible({ timeout: 10_000 });
			await expect(page.getByRole('button', { name: 'Adjust plan' })).toHaveCount(0);
			await expect(page.getByRole('button', { name: 'Abandon plan' })).toHaveCount(0);
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
			await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
		}
	});
});
