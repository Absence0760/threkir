import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * A couch-to-5K plan on its own page (issue #1186). A missed walk-run session
 * is answered with "repeat the week, no penalty" rather than a make-up, and a
 * walk-run week is never judged in kilometres, since its distances are
 * estimates. Once the plan's last session, the 5K, is done, the page
 * celebrates and offers the next step.
 *
 * Runs as a throwaway runner whose plans are cleared after every test.
 */

let runner: SagaUser;

test.beforeAll(async () => {
	[runner] = await createSagaUsers(1, { displayNames: ['Walk Run Runner'] });
});

test.afterAll(async () => {
	await deleteSagaUsers([runner].filter(Boolean));
});

test.afterEach(async () => {
	const { error } = await getAdminClient().from('training_plans').delete().eq('user_id', runner.id);
	if (error) throw error;
});

type Seed = { offset: number; done?: boolean; fiveK?: boolean };

const TIMED = {
	warmup: { duration_s: 300, pace: 'easy' },
	repeats: { count: 8, duration_s: 60, pace_sec_per_km: 732, recovery_duration_s: 90, recovery_pace: 'walk' },
	cooldown: { duration_s: 300, pace: 'easy' }
};

const FIVE_K = {
	warmup: { duration_s: 300, pace: 'easy' },
	repeats: { count: 1, distance_m: 5000, pace_sec_per_km: 732, recovery_pace: 'walk' },
	cooldown: { duration_s: 300, pace: 'easy' }
};

/// A two-week walk-run plan starting `start` days from today; every week is
/// `build` but the last, which is `graduation`.
async function plantPlan(start: number, sessions: Seed[]): Promise<string> {
	const admin = getAdminClient();
	const planId = crypto.randomUUID();
	const { error: planErr } = await admin.from('training_plans').insert({
		id: planId,
		user_id: runner.id,
		name: 'e2e couch to 5k',
		goal_event: 'distance_5k',
		goal_distance_m: 5000,
		start_date: browserDate(start),
		end_date: browserDate(start + 13),
		days_per_week: 3,
		status: 'active'
	});
	if (planErr) throw planErr;
	const weekIds: string[] = [];
	for (let i = 0; i < 2; i++) {
		const id = crypto.randomUUID();
		weekIds.push(id);
		const { error } = await admin.from('plan_weeks').insert({
			id,
			plan_id: planId,
			week_index: i,
			phase: i === 1 ? 'graduation' : 'build',
			target_volume_m: 6150
		});
		if (error) throw error;
	}
	for (const s of sessions) {
		const { error } = await admin.from('plan_workouts').insert({
			week_id: weekIds[Math.floor((s.offset - start) / 7)],
			scheduled_date: browserDate(s.offset),
			kind: 'walk_run',
			target_distance_m: s.fiveK ? 5857 : 2050,
			target_duration_seconds: s.fiveK ? 4260 : 1710,
			structure: s.fiveK ? FIVE_K : TIMED,
			manually_completed: s.done ?? false
		});
		if (error) throw error;
	}
	return planId;
}

async function open(browser: Browser, path: string): Promise<Page> {
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await context.newPage();
	await page.goto(path);
	return page;
}

test.describe('a walk-run plan', () => {
	test('a missed session says to repeat the week, and the week is not judged in km', async ({ browser }) => {
		const planId = await plantPlan(-3, [
			{ offset: -3 },
			{ offset: -1 },
			{ offset: 1 },
			{ offset: 4 },
			{ offset: 6 },
			{ offset: 8, fiveK: true }
		]);
		const page = await open(browser, `/plans/${planId}`);
		try {
			const prompt = page.getByTestId('missed-prompt');
			await expect(prompt).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('missed-prompt-body')).toHaveText(
				"Missing a session costs you nothing. Carry on, or if this week felt hard, run it again before moving up. There's no penalty for repeating a week."
			);
			await expect(page.getByTestId('missed-prompt-make-up')).toHaveCount(0);
			// Two sessions are behind the runner and no run was logged: a road
			// week would read as under plan by their estimated kilometres.
			await expect(page.getByRole('region', { name: 'Plan adherence' })).toHaveCount(0);
			await expect(page.getByText(/So far this week you've run/)).toHaveCount(0);
			await expect(page.getByTestId('walk-run-graduation')).toHaveCount(0);
			// Each session states its minutes, the last its 5K, and no week a km
			// volume: 300 + 8 × 60 + 7 × 90 + 300 = 1710 s reads as 29 min.
			const sizes = page.getByTestId('plan-day-size');
			await expect(sizes).toHaveText(['29 min', '29 min', '29 min', '29 min', '29 min', '5.0 km']);
			await expect(page.getByTestId('plan-week-volume')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});

	test('the 5K done celebrates the graduation and offers a 10K plan next', async ({ browser }) => {
		const planId = await plantPlan(-12, [
			{ offset: -12, done: true },
			{ offset: -10, done: true },
			{ offset: -8, done: true },
			{ offset: -5, done: true },
			{ offset: -3, done: true },
			{ offset: -1, done: true, fiveK: true }
		]);
		const page = await open(browser, `/plans/${planId}`);
		try {
			const card = page.getByTestId('walk-run-graduation');
			await expect(card).toBeVisible({ timeout: 15_000 });
			await expect(card.getByRole('heading', { level: 2 })).toHaveText('You did it: couch to 5K');
			await expect(page.getByTestId('walk-run-graduation-body')).toHaveText(
				'You ran 5K without stopping. You started with one-minute runs between walks.'
			);
			const next = page.getByTestId('walk-run-graduation-ten-k');
			await expect(next).toHaveText('Train for a 10K');
			await expect(next).toHaveAttribute('href', '/plans/new?type=training&goal=10k');
			await next.click();
			await expect(page).toHaveURL(/\/plans\/new\?type=training&goal=10k/);
		} finally {
			await page.context().close();
		}
	});

	test("Home states today's walk-run session in minutes, with no pace", async ({ browser }) => {
		await plantPlan(-2, [{ offset: -2, done: true }, { offset: 0 }, { offset: 2 }, { offset: 5 }, { offset: 7 }, { offset: 9, fiveK: true }]);
		const page = await open(browser, '/dashboard');
		try {
			await expect(page.getByTestId('plan-hero-today-size')).toHaveText('29 min', { timeout: 15_000 });
			await expect(page.getByText(/\/km/)).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});

	test('no celebration while the 5K is still ahead', async ({ browser }) => {
		const planId = await plantPlan(-12, [
			{ offset: -12, done: true },
			{ offset: -10, done: true },
			{ offset: -8, done: true },
			{ offset: -5, done: true },
			{ offset: -3, done: true },
			{ offset: 1, fiveK: true }
		]);
		const page = await open(browser, `/plans/${planId}`);
		try {
			await expect(page.getByRole('heading', { name: 'e2e couch to 5k' })).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('walk-run-graduation')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});
});
