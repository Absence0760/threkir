import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * The dashboard's plan hero once several plans can be active back to back
 * (plan chaining, decisions § 2008). Which plan it shows is pickCurrentPlan's
 * rule: the plan covering today, else the one that ended most recently, else
 * the next to start. `Up next` names the plan queued after the one shown.
 *
 * plan-chaining.spec.ts covers the hero while a plan is under way; this file
 * covers the two states either side of it — the gap after a block has ended
 * and before the next starts, and a runner whose only plan has not started.
 *
 * Runs as a throwaway user whose plans are cleared after every test.
 */

let runner: SagaUser;

test.beforeAll(async () => {
	[runner] = await createSagaUsers(1, { displayNames: ['Up Next Runner'] });
});

test.afterAll(async () => {
	await deleteSagaUsers([runner].filter(Boolean));
});

test.afterEach(async () => {
	const { error } = await getAdminClient().from('training_plans').delete().eq('user_id', runner.id);
	if (error) throw error;
});

async function plantPlan(name: string, startOffset: number, endOffset: number): Promise<string> {
	const admin = getAdminClient();
	const planId = crypto.randomUUID();
	const weekId = crypto.randomUUID();
	const { error: planErr } = await admin.from('training_plans').insert({
		id: planId,
		user_id: runner.id,
		name,
		goal_event: 'distance_10k',
		goal_distance_m: 10_000,
		start_date: browserDate(startOffset),
		end_date: browserDate(endOffset),
		days_per_week: 4,
		status: 'active',
	});
	if (planErr) throw planErr;
	const { error: weekErr } = await admin
		.from('plan_weeks')
		.insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 10_000 });
	if (weekErr) throw weekErr;
	const { error: woErr } = await admin
		.from('plan_workouts')
		.insert({ week_id: weekId, scheduled_date: browserDate(startOffset), kind: 'easy', target_distance_m: 6_000 });
	if (woErr) throw woErr;
	return planId;
}

async function openDashboard(browser: Browser): Promise<Page> {
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await context.newPage();
	await page.goto('/dashboard');
	return page;
}

test.describe('dashboard plan hero around a queued plan', () => {
	test('between two blocks it keeps the ended plan and names the queued one as up next', async ({ browser }) => {
		await plantPlan('e2e up-next ended', -30, -3);
		const queuedId = await plantPlan('e2e up-next queued', 4, 40);
		const page = await openDashboard(browser);
		try {
			const hero = page.locator('.plan-hero');
			await expect(hero.locator('.plan-hero-name')).toHaveText('e2e up-next ended', { timeout: 15_000 });
			await expect(hero.locator('.plan-hero-relation')).toHaveText('Race day past');
			const next = page.getByTestId('plan-hero-next');
			await expect(next).toContainText('Up next: e2e up-next queued');
			await expect(next).toHaveAttribute('href', `/plans/${queuedId}`);
			await expect(page.locator('.plan-promo')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});

	test('a runner whose only plan has not started sees it counting down, with nothing up next', async ({ browser }) => {
		await plantPlan('e2e up-next only queued', 10, 50);
		const page = await openDashboard(browser);
		try {
			const hero = page.locator('.plan-hero');
			await expect(hero.locator('.plan-hero-name')).toHaveText('e2e up-next only queued', { timeout: 15_000 });
			await expect(hero.locator('.plan-hero-relation')).toHaveText('Starts in 10 days');
			await expect(page.getByTestId('plan-hero-next')).toHaveCount(0);
			await expect(page.locator('.plan-promo')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});

	test('with a queued plan two blocks out, up next is the nearer one', async ({ browser }) => {
		await plantPlan('e2e up-next current', -5, 20);
		await plantPlan('e2e up-next far', 60, 90);
		const nearId = await plantPlan('e2e up-next near', 21, 59);
		const page = await openDashboard(browser);
		try {
			await expect(page.locator('.plan-hero .plan-hero-name')).toHaveText('e2e up-next current', { timeout: 15_000 });
			const next = page.getByTestId('plan-hero-next');
			await expect(next).toContainText('Up next: e2e up-next near');
			await expect(next).toHaveAttribute('href', `/plans/${nearId}`);
		} finally {
			await page.context().close();
		}
	});
});
