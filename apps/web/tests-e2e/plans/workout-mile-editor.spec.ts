import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readMaybeRow } from '../fixtures/db-read';
import { acceptCookieConsent, planSectionsOpen } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers } from '../fixtures/saga-users';

/**
 * WorkoutEditor in miles. The form is in the runner's unit; the pace columns
 * are whole seconds per km. A saga user, so the mile preference touches no
 * one else.
 */
test.describe('WorkoutEditor in miles', () => {
	async function seed(runnerId: string, ids: { plan: string; week: string; workout: string }) {
		const admin = getAdminClient();
		await admin.from('user_profiles').update({ preferred_unit: 'mi' }).eq('id', runnerId);
		await admin.from('training_plans').insert({
			id: ids.plan,
			user_id: runnerId,
			name: 'e2e mile editor',
			goal_event: 'distance_10k',
			goal_distance_m: 10000,
			start_date: browserDate(0),
			end_date: browserDate(27),
			status: 'active',
			days_per_week: 3
		});
		await admin
			.from('plan_weeks')
			.insert({ id: ids.week, plan_id: ids.plan, week_index: 0, phase: 'build' });
		await admin.from('plan_workouts').insert({
			id: ids.workout,
			week_id: ids.week,
			scheduled_date: browserDate(2),
			kind: 'easy',
			target_distance_m: 8000,
			target_pace_sec_per_km: 300,
			// 6 s/km is 9.66 s/mi: the editor shows 10.
			target_pace_tolerance_sec: 6
		});
	}

	async function openEditor(page: import('@playwright/test').Page, planId: string) {
		await page.goto(`/plans/${planId}`);
		await page.locator('.day-link', { hasText: /Easy/ }).first().click();
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 10_000 });
		return modal;
	}

	async function readWorkout(id: string) {
		return (await readMaybeRow(
			'plan_workouts by id',
			getAdminClient()
				.from('plan_workouts')
				.select('target_pace_sec_per_km, target_pace_tolerance_sec')
				.eq('id', id)
				.maybeSingle()
		)) as { target_pace_sec_per_km: number | null; target_pace_tolerance_sec: number | null };
	}

	// 5:00/km is 8:02.8/mi, shown as 8:03; 483 s/mi back is 300.12 s/km. The
	// integer column refused the fraction, so this save always failed.
	test('a paced workout saves, its pace rounded to whole seconds per km', async ({
		browser
	}) => {
		const [runner] = await createSagaUsers(1, { displayNames: ['Mile Pace Runner'] });
		const ids = { plan: crypto.randomUUID(), week: crypto.randomUUID(), workout: crypto.randomUUID() };
		const ctx = await browser.newContext({ storageState: runner.storageStatePath });
		await acceptCookieConsent(ctx, planSectionsOpen(runner.id));
		try {
			await seed(runner.id, ids);
			const page = await ctx.newPage();
			const modal = await openEditor(page, ids.plan);
			await modal.getByRole('button', { name: /^Save/ }).click();
			await expect(modal).toHaveCount(0);
			expect((await readWorkout(ids.workout)).target_pace_sec_per_km).toBe(300);
		} finally {
			await ctx.close();
			await getAdminClient().from('training_plans').delete().eq('id', ids.plan);
			await deleteSagaUsers([runner]);
		}
	});

	// The tolerance column is per km too. It used to be shown and saved raw,
	// so ±15 typed beside a /mi pace was stored as ±15 s/km and read back on
	// the workout page as "±24s/mi".
	test('the pace tolerance is shown and saved per mile', async ({ browser }) => {
		const [runner] = await createSagaUsers(1, { displayNames: ['Mile Tolerance Runner'] });
		const ids = { plan: crypto.randomUUID(), week: crypto.randomUUID(), workout: crypto.randomUUID() };
		const ctx = await browser.newContext({ storageState: runner.storageStatePath });
		await acceptCookieConsent(ctx, planSectionsOpen(runner.id));
		try {
			await seed(runner.id, ids);
			const page = await ctx.newPage();
			await page.goto(`/plans/${ids.plan}/workouts/${ids.workout}`);
			await expect(page.locator('.tol')).toHaveText('±10s/mi', { timeout: 15_000 });

			const modal = await openEditor(page, ids.plan);
			await expect(modal).toContainText('± seconds per mi');
			const tolerance = modal.getByLabel(/Pace tolerance/);
			await expect(tolerance).toHaveValue('10');
			await tolerance.fill('15');
			await modal.getByRole('button', { name: /^Save/ }).click();
			await expect(modal).toHaveCount(0);

			// 15 s/mi is 9.32 s/km, stored as 9.
			expect((await readWorkout(ids.workout)).target_pace_tolerance_sec).toBe(9);
			await page.goto(`/plans/${ids.plan}/workouts/${ids.workout}`);
			await expect(page.locator('.tol')).toHaveText('±14s/mi', { timeout: 15_000 });
		} finally {
			await ctx.close();
			await getAdminClient().from('training_plans').delete().eq('id', ids.plan);
			await deleteSagaUsers([runner]);
		}
	});
});
