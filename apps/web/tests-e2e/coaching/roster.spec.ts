import { expect, test } from '../fixtures/test';

import { browserDate, noonOnBrowserDay } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * Multi-athlete coach roster dashboard (coach_roster.md).
 *
 * USER_A (runner) is the COACH; USER_B (alex) + USER_C_PRO (morgan) are the
 * athletes. seed.sql links both to USER_A as active coaching links, and both
 * carry NOW()-relative seeded runs, so the roster renders populated load /
 * recency / risk columns. The spec seeds the two links defensively in
 * beforeEach (idempotent restore of the seed state) so it is independent of any
 * other coaching spec that clears links, then asserts:
 *   - the roster section renders a row per athlete with the load/plan/risk cols,
 *   - clicking a row navigates to the per-athlete review surface,
 *   - a non-coach (no links) sees no roster section at all (the consent gate).
 */

async function seedLinks() {
	const admin = getAdminClient();
	// Clear any stray links for these users, then restore the two seed links.
	await admin.from('coach_athletes').delete().eq('coach_id', USER_A.id);
	await admin.from('coach_athletes').delete().eq('athlete_id', USER_B.id);
	await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
	await admin.from('coach_athletes').insert([
		{
			coach_id: USER_A.id,
			athlete_id: USER_B.id,
			status: 'active',
			invite_token: 'e2e-roster-alex',
			accepted_at: new Date(Date.now() - 30 * 86400_000).toISOString()
		},
		{
			coach_id: USER_A.id,
			athlete_id: USER_C_PRO.id,
			status: 'active',
			invite_token: 'e2e-roster-morgan',
			accepted_at: new Date(Date.now() - 20 * 86400_000).toISOString()
		}
	]);
}

async function clearLinks() {
	const admin = getAdminClient();
	await admin.from('coach_athletes').delete().eq('coach_id', USER_A.id);
	await admin.from('coach_athletes').delete().eq('athlete_id', USER_B.id);
	await admin.from('coach_athletes').delete().eq('athlete_id', USER_C_PRO.id);
}

test.describe('coach roster dashboard', () => {
	test.describe('as the coach', () => {
		test.use({ storageState: USER_A.storageStatePath });
		test.beforeEach(seedLinks);
		test.afterEach(clearLinks);

		test('renders a populated roster and drills into the review surface', async ({ page }) => {
			await page.goto('/coaching');
			await expect(page.getByRole('heading', { level: 1, name: 'Athletes & coaches' })).toBeVisible({
				timeout: 10_000
			});

			const roster = page.getByTestId('roster-section');
			await expect(roster).toBeVisible({ timeout: 10_000 });
			await expect(roster.getByRole('heading', { name: 'Athlete roster' })).toBeVisible();

			// The sortable column headers are present.
			for (const col of ['Athlete', 'Last run', '7-day load', 'Plan %', 'Risk']) {
				await expect(roster.getByRole('button', { name: col })).toBeVisible();
			}

			// One row per seeded athlete, each with a risk chip.
			const rows = page.getByTestId('roster-row');
			await expect(rows).toHaveCount(2, { timeout: 10_000 });
			await expect(page.getByTestId('risk-chip')).toHaveCount(2);

			// Each athlete is linked into the per-athlete review surface.
			await expect(
				roster.locator(`a[href="/coaching/athletes/${USER_B.id}"]`)
			).toBeVisible();
			await expect(
				roster.locator(`a[href="/coaching/athletes/${USER_C_PRO.id}"]`)
			).toBeVisible();

			// Clicking a row navigates to that athlete's review page.
			await roster.locator(`a[href="/coaching/athletes/${USER_C_PRO.id}"]`).click();
			await page.waitForURL(new RegExp(`/coaching/athletes/${USER_C_PRO.id}$`), {
				timeout: 10_000
			});
			await expect(
				page.getByRole('heading', { level: 2, name: 'Recent runs' })
			).toBeVisible({ timeout: 10_000 });
		});
	});

	test.describe('flags', () => {
		test.use({ storageState: USER_A.storageStatePath });
		let planId: string;
		test.beforeEach(async () => {
			await seedLinks();
			const admin = getAdminClient();
			planId = crypto.randomUUID();
			const weekId = crypto.randomUUID();
			expect(
				(
					await admin.from('training_plans').insert({
						id: planId,
						user_id: USER_C_PRO.id,
						name: 'e2e roster miss flag',
						goal_event: 'distance_10k',
						goal_distance_m: 10_000,
						start_date: browserDate(-6),
						end_date: browserDate(7),
						status: 'active',
						days_per_week: 3
					})
				).error
			).toBeNull();
			expect(
				(await admin.from('plan_weeks').insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 15_000 })).error
			).toBeNull();
			expect(
				(
					await admin.from('plan_workouts').insert([
						{ week_id: weekId, scheduled_date: browserDate(-5), kind: 'easy', target_distance_m: 5_000, manually_completed: true },
						{ week_id: weekId, scheduled_date: browserDate(-4), kind: 'rest', manually_completed: false },
						{ week_id: weekId, scheduled_date: browserDate(-3), kind: 'easy', target_distance_m: 5_000, manually_completed: false },
						{ week_id: weekId, scheduled_date: browserDate(-2), kind: 'tempo', target_distance_m: 6_000, manually_completed: false },
						{ week_id: weekId, scheduled_date: browserDate(3), kind: 'easy', target_distance_m: 5_000, manually_completed: false }
					])
				).error
			).toBeNull();
		});
		test.afterEach(async () => {
			await getAdminClient().from('training_plans').delete().eq('id', planId);
			await clearLinks();
		});

		test('an athlete with two misses in a row is flagged', async ({ page }) => {
			await page.goto('/coaching');
			const morgan = page.getByTestId('roster-row').filter({
				has: page.locator(`a[href="/coaching/athletes/${USER_C_PRO.id}"]`)
			});
			const missFlag = morgan.getByTestId('roster-miss-flag');
			await expect(missFlag.locator('.metric-label')).toContainText('2 missed in a row', { timeout: 10_000 });
			await missFlag.getByRole('button', { name: 'About 2 missed in a row' }).click();
			await expect(missFlag.getByTestId('metric-definition-missStreak')).toContainText(
				'counting back from yesterday'
			);
			const alex = page.getByTestId('roster-row').filter({
				has: page.locator(`a[href="/coaching/athletes/${USER_B.id}"]`)
			});
			await expect(alex.getByTestId('roster-miss-flag')).toHaveCount(0);
		});
	});

	test.describe('easy-HR drift', () => {
		// The chip off the real coach_roster_summary: mean heart rate on planned
		// easy runs at the athlete's median easy pace, the last 14 days against
		// the 42 before (migrations 20270915000003 + 20270917000001). Every run
		// covers 8 km in 40 min (5:00/km), so all sit on the median and both
		// windows share a mean pace. The earlier three average 140 bpm and the
		// recent three 150 (three recent runs is the floor), so heart rate at the
		// same pace is 150/140 - 1 = 7.14 % higher and the chip reads +7 %. The
		// second athlete has the same runs and no health-data consent, so the SQL
		// computes nothing for them (decisions § 2092). Saga users, so no seed row is touched and
		// the spec re-runs on a used database. The chip is behind
		// PUBLIC_HR_PRESCRIPTION_ENABLED, on in .env.development; its off state is
		// pinned by src/lib/training/hr_prescription_flag.test.ts.
		test.describe.configure({ timeout: 90_000 });

		let coach: SagaUser;
		let consenting: SagaUser;
		let withheld: SagaUser;

		async function plantEasyRuns(athleteId: string) {
			const admin = getAdminClient();
			const planId = crypto.randomUUID();
			const weekId = crypto.randomUUID();
			expect(
				(
					await admin.from('training_plans').insert({
						id: planId,
						user_id: athleteId,
						name: 'e2e roster hr drift',
						goal_event: 'distance_half',
						goal_distance_m: 21_097,
						start_date: browserDate(-56),
						end_date: browserDate(28),
						status: 'active',
						days_per_week: 3
					})
				).error
			).toBeNull();
			expect(
				(await admin.from('plan_weeks').insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 24_000 })).error
			).toBeNull();
			for (const [daysAgo, avg_bpm] of [
				[34, 140],
				[27, 140],
				[20, 140],
				[11, 150],
				[8, 150],
				[3, 150]
			] as const) {
				const runId = await insertRun({
					user_id: athleteId,
					started_at: noonOnBrowserDay(-daysAgo),
					distance_m: 8_000,
					duration_s: 2_400,
					source: 'app',
					metadata: { avg_bpm }
				});
				expect(
					(
						await admin.from('plan_workouts').insert({
							week_id: weekId,
							scheduled_date: browserDate(-daysAgo),
							kind: 'easy',
							target_distance_m: 8_000,
							completed_run_id: runId
						})
					).error
				).toBeNull();
			}
		}

		test.beforeAll(async () => {
			[coach, consenting, withheld] = await createSagaUsers(3, {
				displayNames: ['Drift Coach', 'Drift Consenting Athlete', 'Drift Withheld Athlete']
			});
			const admin = getAdminClient();
			expect(
				(
					await admin
						.from('user_profiles')
						.update({ health_data_consent_at: new Date().toISOString() })
						.eq('id', consenting.id)
				).error
			).toBeNull();
			expect(
				(
					await admin.from('coach_athletes').insert(
						[consenting, withheld].map((a) => ({
							coach_id: coach.id,
							athlete_id: a.id,
							status: 'active',
							invite_token: `e2e-drift-${a.id}`,
							accepted_at: new Date(Date.now() - 60 * 86400_000).toISOString()
						}))
					)
				).error
			).toBeNull();
			await plantEasyRuns(consenting.id);
			await plantEasyRuns(withheld.id);
		});

		test.afterAll(async () => {
			await deleteSagaUsers([coach, consenting, withheld].filter(Boolean));
		});

		test('a consenting athlete whose easy-run heart rate climbed carries the chip; one without consent does not', async ({
			browser
		}) => {
			const ctx = await browser.newContext({ storageState: coach.storageStatePath });
			try {
				const page = await ctx.newPage();
				await page.goto('/coaching');
				const row = (a: SagaUser) =>
					page.getByTestId('roster-row').filter({ has: page.locator(`a[href="/coaching/athletes/${a.id}"]`) });
				const driftFlag = row(consenting).getByTestId('roster-hr-drift-flag');
				await expect(driftFlag.locator('.metric-label')).toContainText('Easy HR +7%', { timeout: 10_000 });
				await driftFlag.getByRole('button', { name: 'About Easy HR +7%' }).click();
				await expect(driftFlag.getByTestId('metric-definition-easyHrDrift')).toContainText('for the same pace');
				await expect(row(withheld)).toBeVisible();
				await expect(row(withheld).getByTestId('roster-hr-drift-flag')).toHaveCount(0);
			} finally {
				await ctx.close();
			}
		});
	});

	test.describe('as a non-coach', () => {
		// USER_B (alex) coaches nobody, so their roster RPC returns zero rows.
		test.use({ storageState: USER_B.storageStatePath });
		test.beforeEach(clearLinks);
		test.afterEach(clearLinks);

		test('sees no roster section', async ({ page }) => {
			await page.goto('/coaching');
			await expect(page.getByRole('heading', { level: 1, name: 'Athletes & coaches' })).toBeVisible({
				timeout: 10_000
			});
			// The roster section only renders when there are rows (or an error).
			await expect(page.getByTestId('roster-section')).toHaveCount(0, { timeout: 10_000 });
		});
	});
});
