import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Operator Home metrics (/admin/home-metrics, migration 20271201000001,
 * issue #1362).
 *
 * The 42501 boundary and the weekly arithmetic are pinned at the DB layer by
 * admin_home_metrics_test.sql. This spec pins the page on top: the seeded
 * app_admin (USER_A) sees both weekly tables with the Coach entry-point note,
 * and a signed-in non-admin (USER_B) gets the not-authorized card and no
 * figures.
 *
 * Both reads count every user, so the rows are planted on a throwaway user in
 * the previous ISO week (UTC): a run, a Coach message, and one plan day marked
 * done. That keeps either table from falling back to its empty state on a
 * quiet database without touching a seeded user's history.
 */

function previousIsoMonday(): string {
	const now = new Date();
	const sinceMonday = (now.getUTCDay() + 6) % 7;
	return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - sinceMonday - 7))
		.toISOString()
		.slice(0, 10);
}

function addDays(day: string, n: number): string {
	const d = new Date(`${day}T00:00:00Z`);
	d.setUTCDate(d.getUTCDate() + n);
	return d.toISOString().slice(0, 10);
}

const WEEK = previousIsoMonday();
const DAY = addDays(WEEK, 2);
let userId: string | null = null;

test.beforeAll(async () => {
	const admin = getAdminClient();
	const { data, error } = await admin.auth.admin.createUser({
		email: `home-metrics-${Date.now()}@test.com`,
		password: 'testtest',
		email_confirm: true,
	});
	if (error || !data?.user) throw new Error(`home-metrics: createUser failed: ${error?.message}`);
	userId = data.user.id;

	const { error: runErr } = await admin.from('runs').insert({
		user_id: userId,
		started_at: `${DAY}T12:00:00Z`,
		duration_s: 1800,
		distance_m: 5000,
		source: 'app',
	});
	if (runErr) throw new Error(`home-metrics: run insert failed: ${runErr.message}`);

	const { error: coachErr } = await admin
		.from('user_coach_usage')
		.insert({ user_id: userId, usage_date: DAY, message_count: 1 });
	if (coachErr) throw new Error(`home-metrics: coach usage insert failed: ${coachErr.message}`);

	const { data: plan, error: planErr } = await admin
		.from('training_plans')
		.insert({
			user_id: userId,
			name: 'Home metrics e2e plan',
			goal_event: 'distance_10k',
			goal_distance_m: 10000,
			start_date: WEEK,
			end_date: addDays(WEEK, 6),
			days_per_week: 4,
			status: 'completed',
		})
		.select('id')
		.single();
	if (planErr || !plan) throw new Error(`home-metrics: plan insert failed: ${planErr?.message}`);
	const { data: week, error: weekErr } = await admin
		.from('plan_weeks')
		.insert({ plan_id: plan.id, week_index: 0, phase: 'base' })
		.select('id')
		.single();
	if (weekErr || !week) throw new Error(`home-metrics: plan week insert failed: ${weekErr?.message}`);
	const { error: dayErr } = await admin.from('plan_workouts').insert({
		week_id: week.id,
		scheduled_date: addDays(WEEK, 3),
		kind: 'easy',
		target_distance_m: 5000,
		manually_completed: true,
	});
	if (dayErr) throw new Error(`home-metrics: plan day insert failed: ${dayErr.message}`);
});

test.afterAll(async () => {
	// Deleting the auth user cascades to its runs, Coach usage and plan.
	if (userId) await getAdminClient().auth.admin.deleteUser(userId);
});

test.describe('admin home metrics — operator view', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('both weekly tables render with the planted week counted', async ({ page }) => {
		await page.goto('/admin/home-metrics');

		const coach = page.getByTestId('home-metrics-coach');
		await expect(coach).toBeVisible({ timeout: 15_000 });
		await expect(coach.getByTestId('home-metrics-coach-row')).toHaveCount(16);
		const coachRow = coach.locator(`[data-testid="home-metrics-coach-row"][data-week="${WEEK}"]`);
		await expect(coachRow).toBeVisible();
		await expect(coachRow).toContainText('%');
		await expect(page.getByTestId('home-metrics-coach-note')).toContainText('every entry point');

		const plan = page.getByTestId('home-metrics-plan');
		await expect(plan.getByTestId('home-metrics-plan-row')).toHaveCount(16);
		const planRow = plan.locator(`[data-testid="home-metrics-plan-row"][data-week="${WEEK}"]`);
		await expect(planRow).toBeVisible();
		await expect(planRow).toContainText('%');

		await expect(page.getByText('ISO weeks starting Monday, in UTC')).toBeVisible();
	});
});

test.describe('admin home metrics — non-admin', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('a signed-in non-admin sees the not-authorized card and no figures', async ({ page }) => {
		await page.goto('/admin/home-metrics');
		await expect(page.getByTestId('home-metrics-not-authorized')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('home-metrics-coach')).toHaveCount(0);
		await expect(page.getByTestId('home-metrics-plan')).toHaveCount(0);
	});
});
