import { expect, test } from '@playwright/test';

import { browserDate, noonOnBrowserDay } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers } from '../fixtures/saga-users';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] adherence feedback (roadmap Phase 3 — Adherence feedback).
 *
 * Two owner-only flags driven by lib/training/plan_adherence.ts:
 *   - weekly mileage drift (>20% over / under the planned week volume)
 *   - a missed long run's make-up / skip recommendation
 *
 * The pure logic is unit-tested; this pins the Svelte wiring — the
 * current-week date window, the planned-volume baseline, the run
 * summation, and the conditional render. We seed a throwaway plan whose
 * start_date puts "today" inside week 0 (status `completed` to dodge the
 * one-active-plan unique index — adherence gates on dates, not status),
 * a build week with a 40 km target, an uncompleted long run dated
 * yesterday, and two runs that over-run the week to ~52 km (+30%).
 */

test.describe('/plans/[id] adherence flags', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('over-running + a missed long run both surface their flags', async ({ page }) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const week0Id = crypto.randomUUID();
		const week1Id = crypto.randomUUID();
		const dayMs = 24 * 3600 * 1000;
		const iso = (d: Date) => d.toISOString().slice(0, 10);
		const start = new Date(Date.now() - 3 * dayMs); // today is day 3 → week 0
		const startIso = iso(start);
		const endIso = iso(new Date(Date.now() + 35 * dayMs)); // >21d out → no RaceDayPanel
		const yesterdayIso = iso(new Date(Date.now() - dayMs));

		const runIds: string[] = [];
		try {
			await admin.from('training_plans').insert({
				id: planId,
				user_id: USER_A.id,
				name: 'e2e adherence',
				goal_event: 'distance_full',
				goal_distance_m: 42195,
				goal_time_seconds: null,
				start_date: startIso,
				end_date: endIso,
				status: 'completed',
				days_per_week: 5
			});
			// Two build weeks, equal volume → no step-back, so a missed
			// long run reads "make up" (not "recovery soon").
			await admin.from('plan_weeks').insert([
				{ id: week0Id, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 40_000 },
				{ id: week1Id, plan_id: planId, week_index: 1, phase: 'build', target_volume_m: 40_000 }
			]);
			// A long run dated yesterday, left uncompleted.
			await admin.from('plan_workouts').insert({
				week_id: week0Id,
				scheduled_date: yesterdayIso,
				kind: 'long',
				target_distance_m: 20_000
			});

			// Two runs inside week 0 summing ~52 km → +30% over the 40 km plan.
			for (let i = 0; i < 2; i++) {
				const id = await insertRun({
					user_id: USER_A.id,
					started_at: new Date(Date.now() - (i + 1) * dayMs).toISOString(),
					distance_m: 26_000,
					duration_s: 7800
				});
				runIds.push(id);
			}

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e adherence' }))
				.toBeVisible({ timeout: 10_000 });

			// Over-running drift flag.
			await expect(page.locator('.adherence-flag.drift-over')).toBeVisible();
			await expect(page.locator('.adherence-flag.drift-over')).toHaveText(/over plan/i);

			// Missed long run → make-up recommendation.
			await expect(page.locator('.adherence-flag.missed-make_up')).toBeVisible();
			await expect(page.locator('.adherence-flag.missed-make_up')).toHaveText(/long run/i);
		} finally {
			for (const id of runIds) await deleteRun(id);
			// FK cascade clears weeks + workouts when the plan goes.
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});

	// The under-running flag used to read "Running 100% under plan this week —
	// the planned volume drives the adaptation.", which means "you have run
	// none of it" and reads as praise (#902 section 1.7). It now states the two
	// distances, and the planned one is what the plan asked for up to TODAY
	// (#902 still-open 4). A saga user, so no seeded run can land in the week.
	//
	// Both cases below share one seed: a plan starting three days ago, so today
	// is the fourth day of week 0, with five 8 km days from day 0 to day 4. The
	// 24 km on days 0-2 has come due; the 16 km on today and tomorrow has not.
	async function seedWeek(
		admin: ReturnType<typeof getAdminClient>,
		planId: string,
		userId: string,
		name: string
	) {
		const weekId = crypto.randomUUID();
		await admin.from('training_plans').insert({
			id: planId,
			user_id: userId,
			name,
			goal_event: 'distance_full',
			goal_distance_m: 42195,
			goal_time_seconds: null,
			start_date: browserDate(-3),
			end_date: browserDate(35),
			status: 'active',
			days_per_week: 5
		});
		await admin.from('plan_weeks').insert({
			id: weekId,
			plan_id: planId,
			week_index: 0,
			phase: 'build',
			target_volume_m: 40_000
		});
		await admin.from('plan_workouts').insert(
			[-3, -2, -1, 0, 1].map((offset) => ({
				week_id: weekId,
				scheduled_date: browserDate(offset),
				kind: 'easy',
				target_distance_m: 8_000
			}))
		);
	}

	test('under-running states what was run against what the plan asked for so far', async ({
		browser
	}) => {
		const [runner] = await createSagaUsers(1, { displayNames: ['Under Plan Runner'] });
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const ctx = await browser.newContext({ storageState: runner.storageStatePath });
		try {
			await seedWeek(admin, planId, runner.id, 'e2e under plan');
			await insertRun({
				user_id: runner.id,
				started_at: noonOnBrowserDay(-1),
				distance_m: 10_000,
				duration_s: 3_000
			});

			const page = await ctx.newPage();
			await page.goto(`/plans/${planId}`);
			const flag = page.locator('.adherence-flag.drift-under');
			await expect(flag).toBeVisible({ timeout: 15_000 });
			// 24 km due by now, not the week's full 40 km.
			await expect(flag).toHaveText(
				/So far this week you've run 10\.0 km of the 24\.0 km due by now\./
			);
			await expect(flag).not.toContainText('%');
		} finally {
			await ctx.close();
			await admin.from('training_plans').delete().eq('id', planId);
			await deleteSagaUsers([runner]);
		}
	});

	// The defect behind #902 still-open 4: against the whole week's 40 km, a
	// runner who had banked every session due so far read 40% under plan on the
	// fourth day, every week, until the week ended.
	test('a runner level with the plan to date is not flagged mid-week', async ({ browser }) => {
		const [runner] = await createSagaUsers(1, { displayNames: ['On Plan Runner'] });
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const ctx = await browser.newContext({ storageState: runner.storageStatePath });
		try {
			await seedWeek(admin, planId, runner.id, 'e2e on plan to date');
			for (const offset of [-3, -2, -1]) {
				await insertRun({
					user_id: runner.id,
					started_at: noonOnBrowserDay(offset),
					distance_m: 8_000,
					duration_s: 2_400
				});
			}

			const page = await ctx.newPage();
			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e on plan to date' }))
				.toBeVisible({ timeout: 15_000 });
			await expect(page.locator('.adherence-flag')).toHaveCount(0);
		} finally {
			await ctx.close();
			await admin.from('training_plans').delete().eq('id', planId);
			await deleteSagaUsers([runner]);
		}
	});
});
