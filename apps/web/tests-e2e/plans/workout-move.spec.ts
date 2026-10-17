import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] — moving a workout to another day from the workout editor
 * (issue #1186, decisions § 2073). The week is seeded the way the generator
 * writes one, a row on every day with rest days included, so every target day
 * is occupied and the move is always a swap. Throwaway plan (status
 * `completed` to dodge the active-plan overlap constraint).
 */
test.describe('/plans/[id] — move a workout to another day', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const admin = getAdminClient();
	let planId: string;
	let tempoId: string;
	let thursdayRestId: string;

	test.beforeEach(async () => {
		planId = crypto.randomUUID();
		const weekId = crypto.randomUUID();
		tempoId = crypto.randomUUID();
		thursdayRestId = crypto.randomUUID();
		const { error: planErr } = await admin.from('training_plans').insert({
			id: planId,
			user_id: USER_A.id,
			name: 'e2e workout move',
			goal_event: 'distance_10k',
			goal_distance_m: 10_000,
			start_date: browserDate(0),
			end_date: browserDate(6),
			status: 'completed',
			days_per_week: 3,
		});
		expect(planErr).toBeNull();
		const { error: weekErr } = await admin
			.from('plan_weeks')
			.insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 26_000 });
		expect(weekErr).toBeNull();
		const kinds = ['rest', 'easy', 'rest', 'tempo', 'rest', 'long', 'rest'];
		const { error: woErr } = await admin.from('plan_workouts').insert(
			kinds.map((kind, day) => ({
				id: kind === 'tempo' ? tempoId : day === 4 ? thursdayRestId : crypto.randomUUID(),
				week_id: weekId,
				scheduled_date: browserDate(day),
				kind,
				target_distance_m: kind === 'rest' ? null : kind === 'long' ? 12_000 : 7_000,
			})),
		);
		expect(woErr).toBeNull();
	});

	test.afterEach(async () => {
		await admin.from('training_plans').delete().eq('id', planId);
	});

	async function readDate(id: string) {
		return (await admin.from('plan_workouts').select('scheduled_date').eq('id', id).single()).data
			?.scheduled_date;
	}

	test('moving onto a rest day trades the two days', async ({ page }) => {
		await page.goto(`/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: 'e2e workout move' })).toBeVisible({
			timeout: 10_000,
		});
		await page.locator('.day-link', { hasText: 'Tempo' }).first().click();

		const day = page.getByTestId('workout-move-day');
		await expect(day).toBeVisible();
		await expect(day.locator(`option[value="${browserDate(4)}"]`)).toContainText('swaps with Rest');
		await day.selectOption(browserDate(4));
		await page.getByRole('button', { name: 'Save', exact: true }).click();

		await expect.poll(() => readDate(tempoId)).toBe(browserDate(4));
		expect(await readDate(thursdayRestId)).toBe(browserDate(3));
	});

	test('shifting a dense week by a number of days that is not a week moves every row', async ({ page }) => {
		await page.goto(`/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: 'e2e workout move' })).toBeVisible({
			timeout: 10_000,
		});
		await page.getByRole('button', { name: 'Adjust plan' }).click();
		const adjust = page.getByTestId('adjust-plan-dialog');
		await adjust.locator('.shift-control input').fill('2');
		await adjust.getByRole('button', { name: 'Shift dates' }).click();
		await page.getByTestId('bulk-confirm-dialog').getByRole('button', { name: 'Apply' }).click();

		await expect.poll(() => readDate(tempoId)).toBe(browserDate(5));
		expect(await readDate(thursdayRestId)).toBe(browserDate(6));
	});
});
