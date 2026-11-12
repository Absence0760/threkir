import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { clearUserSettingKey, setUserSetting } from '../fixtures/simulate';

/**
 * Grisnir lies down in the plan hero on a rest day, with his one dry line, and
 * only then (#1360): a scheduled rest workout and a day with nothing scheduled
 * both count, a run day does not, and the runner's `show_mascot` setting off
 * leaves him out.
 *
 * Runs as a throwaway runner whose plan is cleared after every test.
 */

let runner: SagaUser;

test.beforeAll(async () => {
	[runner] = await createSagaUsers(1, { displayNames: ['Rest Day Runner'] });
});

test.afterAll(async () => {
	await deleteSagaUsers([runner].filter(Boolean));
});

test.afterEach(async () => {
	const { error } = await getAdminClient().from('training_plans').delete().eq('user_id', runner.id);
	if (error) throw error;
	await clearUserSettingKey(runner.id, 'show_mascot');
});

/// An active one-week plan that started yesterday, with `today` as today's
/// workout kind, or nothing scheduled today when null.
async function plantPlan(today: 'rest' | 'easy' | null): Promise<void> {
	const admin = getAdminClient();
	const planId = crypto.randomUUID();
	const weekId = crypto.randomUUID();
	const plan = await admin.from('training_plans').insert({
		id: planId,
		user_id: runner.id,
		name: 'e2e rest day plan',
		goal_event: 'distance_10k',
		goal_distance_m: 10000,
		start_date: browserDate(-1),
		end_date: browserDate(13),
		days_per_week: 3,
		status: 'active',
	});
	if (plan.error) throw plan.error;
	const week = await admin.from('plan_weeks').insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 15000 });
	if (week.error) throw week.error;
	const rows = [{ offset: 2, kind: 'easy', target_distance_m: 5000 }];
	if (today) rows.push({ offset: 0, kind: today, target_distance_m: today === 'rest' ? 0 : 5000 });
	for (const r of rows) {
		const { error } = await admin.from('plan_workouts').insert({
			week_id: weekId,
			scheduled_date: browserDate(r.offset),
			kind: r.kind,
			target_distance_m: r.target_distance_m || null,
			manually_completed: false,
		});
		if (error) throw error;
	}
}

async function openDashboard(browser: Browser): Promise<Page> {
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await context.newPage();
	await page.goto('/dashboard');
	await expect(page.locator('.plan-hero-today')).toBeVisible({ timeout: 15_000 });
	return page;
}

test('a scheduled rest day shows Grisnir resting and his one line', async ({ browser }) => {
	await plantPlan('rest');
	const page = await openDashboard(browser);
	try {
		const grisnir = page.getByTestId('rest-day-grisnir');
		await expect(grisnir).toBeVisible();
		await expect(grisnir).toHaveText("Back by morning, like Thor's goats.");
		await expect(grisnir.locator('img')).toHaveAttribute('alt', '');
		await expect.poll(() => grisnir.locator('img').evaluate((img: HTMLImageElement) => img.naturalWidth)).toBeGreaterThan(0);
	} finally {
		await page.context().close();
	}
});

test('a plan day with nothing scheduled is a rest day too', async ({ browser }) => {
	await plantPlan(null);
	const page = await openDashboard(browser);
	try {
		await expect(page.getByTestId('rest-day-grisnir')).toBeVisible();
	} finally {
		await page.context().close();
	}
});

test('a run day has no Grisnir', async ({ browser }) => {
	await plantPlan('easy');
	const page = await openDashboard(browser);
	try {
		await expect(page.getByTestId('plan-hero-today-size')).toBeVisible();
		await expect(page.getByTestId('rest-day-grisnir')).toHaveCount(0);
	} finally {
		await page.context().close();
	}
});

test('show_mascot off keeps him off the rest day', async ({ browser }) => {
	await plantPlan('rest');
	await setUserSetting(runner.id, 'show_mascot', false);
	const page = await openDashboard(browser);
	try {
		// He is off until the settings land, so wait for them before judging.
		await page.waitForLoadState('networkidle');
		await expect(page.getByTestId('rest-day-grisnir')).toHaveCount(0);
	} finally {
		await page.context().close();
	}
});
