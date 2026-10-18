import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /plans/[id] — who gets the workout editor (issue #1186). The plan_workouts
 * update policies admit the owner and an athlete's active coach (non-template
 * plans only), so the editor opens for them and for nobody else: a stranger
 * reading a public-library template used to get an editor whose save RLS
 * refused. They now land on the read-only workout page instead.
 */
test.describe('/plans/[id] — the workout editor is offered only to who may save', () => {
	test.use({ storageState: USER_B.storageStatePath });

	const admin = getAdminClient();
	let planId: string;
	let tempoId: string;

	async function seedPlan(ownerId: string, template: boolean): Promise<void> {
		planId = crypto.randomUUID();
		tempoId = crypto.randomUUID();
		const weekId = crypto.randomUUID();
		const { error: planErr } = await admin.from('training_plans').insert({
			id: planId,
			user_id: ownerId,
			name: 'e2e workout edit gate',
			goal_event: 'distance_10k',
			goal_distance_m: 10_000,
			start_date: browserDate(0),
			end_date: browserDate(6),
			status: 'completed',
			days_per_week: 3,
			is_template: template,
			is_public_template: template
		});
		expect(planErr).toBeNull();
		const { error: weekErr } = await admin
			.from('plan_weeks')
			.insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 7_000 });
		expect(weekErr).toBeNull();
		const { error: woErr } = await admin.from('plan_workouts').insert({
			id: tempoId,
			week_id: weekId,
			scheduled_date: browserDate(1),
			kind: 'tempo',
			target_distance_m: 7_000
		});
		expect(woErr).toBeNull();
	}

	async function cleanLinks(): Promise<void> {
		await admin.from('coach_athletes').delete().eq('coach_id', USER_B.id);
		await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
	}

	test.beforeEach(cleanLinks);
	test.afterEach(async () => {
		await admin.from('training_plans').delete().eq('id', planId);
		await cleanLinks();
	});

	test('a stranger on a public template opens the read-only workout page', async ({ page }) => {
		await seedPlan(USER_A.id, true);
		await page.goto(`/plans/${planId}`);
		await expect(
			page.getByRole('heading', { level: 1, name: 'e2e workout edit gate' })
		).toBeVisible({ timeout: 10_000 });
		await page.locator('.day-link', { hasText: 'Tempo' }).first().click();

		await expect(page).toHaveURL(new RegExp(`/plans/${planId}/workouts/${tempoId}$`));
		await expect(page.getByRole('button', { name: 'Save', exact: true })).toHaveCount(0);
	});

	test("an athlete's active coach gets the editor", async ({ page }) => {
		await seedPlan(USER_C_PRO.id, false);
		const { error } = await admin.from('coach_athletes').insert({
			coach_id: USER_B.id,
			athlete_id: USER_C_PRO.id,
			status: 'active',
			invite_token: 'e2eworkouteditgate00000000000001',
			accepted_at: new Date().toISOString()
		});
		expect(error).toBeNull();

		await page.goto(`/plans/${planId}`);
		await expect(
			page.getByRole('heading', { level: 1, name: 'e2e workout edit gate' })
		).toBeVisible({ timeout: 10_000 });
		await page.locator('.day-link', { hasText: 'Tempo' }).first().click();

		await expect(page.getByRole('button', { name: 'Save', exact: true })).toBeVisible();
		await expect(page).toHaveURL(new RegExp(`/plans/${planId}$`));
	});
});
