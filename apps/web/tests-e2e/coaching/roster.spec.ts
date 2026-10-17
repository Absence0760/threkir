import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
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

		test('an athlete with two misses in a row is flagged, and the easy-HR drift chip renders from the RPC', async ({
			page
		}) => {
			// The drift needs weeks of HR-bearing runs linked to planned easy
			// workouts; coach_roster_miss_hr_drift_test.sql measures that SQL. Here
			// the response is patched so the chip's rendering is what is asserted.
			await page.route('**/rest/v1/rpc/coach_roster_summary**', async (route) => {
				const response = await route.fetch();
				const rows = (await response.json()) as Array<Record<string, unknown>>;
				for (const r of rows) if (r.athlete_id === USER_C_PRO.id) r.easy_hr_drift_pct = 6.6;
				await route.fulfill({ response, json: rows });
			});
			await page.goto('/coaching');
			const morgan = page.getByTestId('roster-row').filter({
				has: page.locator(`a[href="/coaching/athletes/${USER_C_PRO.id}"]`)
			});
			await expect(morgan.getByTestId('roster-miss-flag')).toHaveText('2 missed in a row', { timeout: 10_000 });
			await expect(morgan.getByTestId('roster-hr-drift-flag')).toHaveText('Easy HR +7%');
			const alex = page.getByTestId('roster-row').filter({
				has: page.locator(`a[href="/coaching/athletes/${USER_B.id}"]`)
			});
			await expect(alex.getByTestId('roster-miss-flag')).toHaveCount(0);
			await expect(alex.getByTestId('roster-hr-drift-flag')).toHaveCount(0);
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
