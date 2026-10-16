import { expect, test } from '../fixtures/test';

import { readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * A runner can plan an ultra by hand (issue #1181): picking "56 km" in the
 * wizard's goal list stores a custom goal of 56 000 m, and the plan the
 * generator builds from it is the ultra shape — the 16-week ultra default,
 * long runs carrying a time-on-feet duration and no pace, and the race day
 * at the full distance. The generator itself is unit-tested on both
 * platforms; this pins the wizard wiring from the select to the saved rows.
 *
 * Runs as a throwaway user so the new active plan overlaps nothing.
 */

let users: SagaUser[] = [];

test.beforeAll(async () => {
	users = await createSagaUsers(1, { displayNames: ['Ultra Planner'] });
});

test.afterAll(async () => {
	await deleteSagaUsers(users);
});

test('the wizard creates a 56 km ultra plan with time-on-feet long runs', async ({ browser }) => {
	const [runner] = users;
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await context.newPage();
	const name = `e2e Two Oceans ${Date.now()}`;

	await page.goto('/plans/new?type=training');
	const form = page.locator('form.plan-editor');
	await expect(form.locator('.week-item').first()).toBeVisible({ timeout: 10_000 });

	await form.getByPlaceholder('Autumn half marathon').fill(name);
	await form.getByLabel('Goal race').selectOption({ label: '56 km' });
	await expect(form.getByTestId('plan-ultra-distance')).toBeVisible();
	// The preview follows the ultra defaults: 16 weeks for 56 km and 24 for
	// 100 mi, where a plain custom goal would have stayed at 12.
	await expect(form.locator('.week-item')).toHaveCount(16);
	await form.getByLabel('Goal race').selectOption({ label: '100 mi' });
	await expect(form.locator('.week-item')).toHaveCount(24);
	await form.getByLabel('Goal race').selectOption({ label: '56 km' });
	await expect(form.locator('.week-item')).toHaveCount(16);

	const submit = form.locator('button[type="submit"]');
	await expect(submit).toBeEnabled({ timeout: 5_000 });
	await submit.click();
	await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
	const planId = new URL(page.url()).pathname.split('/').pop()!;

	const admin = getAdminClient();
	const plan = await readRow(
		'the created ultra plan',
		admin.from('training_plans').select('user_id, goal_event, goal_distance_m').eq('id', planId).single()
	);
	expect(plan.user_id).toBe(runner.id);
	expect(plan.goal_event).toBe('custom');
	expect(Number(plan.goal_distance_m)).toBe(56_000);

	const weeks = await readRows(
		'weeks of the ultra plan',
		admin.from('plan_weeks').select('id').eq('plan_id', planId)
	);
	expect(weeks).toHaveLength(16);
	const workouts = await readRows(
		'workouts of the ultra plan',
		admin
			.from('plan_workouts')
			.select('kind, target_distance_m, target_duration_seconds, target_pace_sec_per_km')
			.in(
				'week_id',
				weeks.map((w) => w.id)
			)
	);
	const longs = workouts.filter((w) => w.kind === 'long');
	expect(longs.length).toBeGreaterThan(10);
	for (const w of longs) {
		expect(w.target_duration_seconds).toBeGreaterThanOrEqual(3600);
		expect(w.target_duration_seconds).toBeLessThanOrEqual(3.5 * 3600);
		expect(w.target_pace_sec_per_km).toBeNull();
	}
	const races = workouts.filter((w) => w.kind === 'race');
	expect(races.map((w) => Number(w.target_distance_m))).toEqual([56_000]);

	await context.close();
});
