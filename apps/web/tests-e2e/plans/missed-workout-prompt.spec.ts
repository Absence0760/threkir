import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readMaybeRow, readRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * The Today card asks once about the runner's most recent missed workout
 * (issue #1186, decisions § 2122): "Make it up" for a long run the engine
 * would make up, through the re-plan preview the runner accepts; "Let it go"
 * for everything else. Either answer is stored on the workout
 * (`missed_ack_at`), so it is never asked again, on any device.
 *
 * Runs as a throwaway runner whose plans are cleared after every test. Each
 * plan starts 14 days ago, one week per 7 days, every week `build` at 30 km
 * unless the test says otherwise, so no recovery week is ever imminent.
 */

let runner: SagaUser;

test.beforeAll(async () => {
	[runner] = await createSagaUsers(1, { displayNames: ['Missed Prompt Runner'] });
});

test.afterAll(async () => {
	await deleteSagaUsers([runner].filter(Boolean));
});

test.afterEach(async () => {
	const { error } = await getAdminClient().from('training_plans').delete().eq('user_id', runner.id);
	if (error) throw error;
});

type Seed = {
	key: string;
	offset: number;
	kind: 'long' | 'easy' | 'tempo' | 'interval';
	distanceM: number;
	done?: boolean;
	answered?: boolean;
};

const START = -14;

async function plantPlan(
	workouts: Seed[],
	opts: { status?: 'active' | 'paused'; phases?: Record<number, string> } = {}
): Promise<{ planId: string; ids: Record<string, string> }> {
	const admin = getAdminClient();
	const planId = crypto.randomUUID();
	const { error: planErr } = await admin.from('training_plans').insert({
		id: planId,
		user_id: runner.id,
		name: 'e2e missed prompt',
		goal_event: 'distance_half',
		goal_distance_m: 21_097,
		start_date: browserDate(START),
		end_date: browserDate(START + 48),
		days_per_week: 4,
		status: opts.status ?? 'active'
	});
	if (planErr) throw planErr;
	const weekIds: string[] = [];
	for (let i = 0; i < 7; i++) {
		const id = crypto.randomUUID();
		weekIds.push(id);
		const { error } = await admin.from('plan_weeks').insert({
			id,
			plan_id: planId,
			week_index: i,
			phase: opts.phases?.[i] ?? 'build',
			target_volume_m: 30_000
		});
		if (error) throw error;
	}
	const ids: Record<string, string> = {};
	for (const w of workouts) {
		const id = crypto.randomUUID();
		ids[w.key] = id;
		const { error } = await admin.from('plan_workouts').insert({
			id,
			week_id: weekIds[Math.floor((w.offset - START) / 7)],
			scheduled_date: browserDate(w.offset),
			kind: w.kind,
			target_distance_m: w.distanceM,
			manually_completed: w.done ?? false,
			missed_ack_at: w.answered ? new Date().toISOString() : null
		});
		if (error) throw error;
	}
	return { planId, ids };
}

async function open(browser: Browser, path: string): Promise<Page> {
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await context.newPage();
	await page.goto(path);
	return page;
}

async function workout(id: string): Promise<{ missed_ack_at: string | null; target_distance_m: number | null }> {
	return readRow(
		`workout ${id}`,
		getAdminClient().from('plan_workouts').select('missed_ack_at, target_distance_m').eq('id', id).single()
	);
}

const LONG_MISS: Seed[] = [
	{ key: 'missed', offset: -3, kind: 'long', distanceM: 16_000 },
	{ key: 'easy', offset: -1, kind: 'easy', distanceM: 6_000, done: true },
	{ key: 'next', offset: 4, kind: 'long', distanceM: 14_000 }
];

test.describe('the missed-workout prompt', () => {
	test('plan page: Make it up previews the stretched long run and answers the miss on apply', async ({ browser }) => {
		const { planId, ids } = await plantPlan(LONG_MISS);
		const page = await open(browser, `/plans/${planId}`);
		try {
			const prompt = page.getByTestId('missed-prompt');
			await expect(prompt).toBeVisible({ timeout: 15_000 });
			await expect(prompt.getByRole('heading')).toContainText('Missed: Long run on');
			await expect(page.getByTestId('missed-prompt-body')).toHaveText(
				"Make it up by stretching your next long run from 14.0 km to 16.0 km. You'll see the change before it's saved."
			);
			const makeUp = page.getByTestId('missed-prompt-make-up');
			await expect(makeUp).toContainText('Recommended');
			await expect(page.getByTestId('missed-prompt-let-go')).not.toContainText('Recommended');

			await makeUp.click();
			const preview = page.getByRole('region', { name: 'Proposed plan changes' });
			await expect(preview).toBeVisible();
			await expect(preview).toContainText('Long run 14.0 km → 16.0 km');
			// Nothing is written until the runner accepts the preview.
			expect((await workout(ids.next)).target_distance_m).toBe(14_000);
			expect((await workout(ids.missed)).missed_ack_at).toBeNull();

			await preview.getByRole('button', { name: 'Apply changes' }).click();
			await expect(prompt).toHaveCount(0, { timeout: 10_000 });
			expect((await workout(ids.next)).target_distance_m).toBe(16_000);
			expect((await workout(ids.missed)).missed_ack_at).not.toBeNull();
		} finally {
			await page.context().close();
		}
	});

	// An answered miss is off the books (decisions § 2125): once the make-up is
	// applied, Re-plan must not stretch the same long run a second time.
	test('after Make it up is applied, Re-plan proposes no second stretch', async ({ browser }) => {
		const { planId, ids } = await plantPlan([
			{ key: 'missed', offset: -3, kind: 'long', distanceM: 20_000 },
			{ key: 'easy', offset: -1, kind: 'easy', distanceM: 6_000, done: true },
			{ key: 'next', offset: 4, kind: 'long', distanceM: 14_000 }
		]);
		const page = await open(browser, `/plans/${planId}`);
		try {
			await page.getByTestId('missed-prompt-make-up').click({ timeout: 15_000 });
			const preview = page.getByRole('region', { name: 'Proposed plan changes' });
			await expect(preview).toContainText('Long run 14.0 km → 16.1 km');
			await preview.getByRole('button', { name: 'Apply changes' }).click();
			await expect(page.getByTestId('missed-prompt')).toHaveCount(0, { timeout: 10_000 });
			expect((await workout(ids.next)).target_distance_m).toBe(16_100);

			await page.getByRole('button', { name: 'Adjust plan' }).click();
			await page
				.getByTestId('adjust-plan-dialog')
				.getByRole('button', { name: 'Re-plan remaining weeks' })
				.click();
			await expect(page.getByText("Your plan's on track — nothing to adjust.")).toBeVisible();
			await expect(preview).toHaveCount(0);
			expect((await workout(ids.next)).target_distance_m).toBe(16_100);
		} finally {
			await page.context().close();
		}
	});

	test('a Re-plan opened over an unapplied make-up applies as a re-plan, not as an answer', async ({
		browser
	}) => {
		const { planId, ids } = await plantPlan(LONG_MISS);
		const page = await open(browser, `/plans/${planId}`);
		try {
			await page.getByTestId('missed-prompt-make-up').click({ timeout: 15_000 });
			const preview = page.getByRole('region', { name: 'Proposed plan changes' });
			await expect(preview).toContainText('Long run 14.0 km → 16.0 km');

			await page.getByRole('button', { name: 'Adjust plan' }).click();
			await page
				.getByTestId('adjust-plan-dialog')
				.getByRole('button', { name: 'Re-plan remaining weeks' })
				.click();
			await expect(preview).toContainText('16.0 km');
			await preview.getByRole('button', { name: 'Apply changes' }).click();
			await expect
				.poll(async () => (await workout(ids.next)).target_distance_m, { timeout: 10_000 })
				.toBe(16_000);
			// Only the make-up preview answers the miss; a plain re-plan leaves it asked.
			expect((await workout(ids.missed)).missed_ack_at).toBeNull();
		} finally {
			await page.context().close();
		}
	});

	test('cancelling the make-up preview records nothing and keeps the question', async ({ browser }) => {
		const { planId, ids } = await plantPlan(LONG_MISS);
		const page = await open(browser, `/plans/${planId}`);
		try {
			await page.getByTestId('missed-prompt-make-up').click({ timeout: 15_000 });
			const preview = page.getByRole('region', { name: 'Proposed plan changes' });
			await preview.getByRole('button', { name: 'Cancel' }).click();
			await expect(preview).toHaveCount(0);
			await expect(page.getByTestId('missed-prompt')).toBeVisible();
			expect(await workout(ids.missed)).toEqual({ missed_ack_at: null, target_distance_m: 16_000 });
			expect((await workout(ids.next)).target_distance_m).toBe(14_000);
		} finally {
			await page.context().close();
		}
	});

	test('Home: Make it up opens the preview on the plan page and clears the request from the URL', async ({
		browser
	}) => {
		const { planId, ids } = await plantPlan(LONG_MISS);
		const page = await open(browser, '/dashboard');
		try {
			const makeUp = page.getByTestId('missed-prompt-make-up');
			await expect(makeUp).toHaveAttribute('href', `/plans/${planId}?makeup=1`, { timeout: 15_000 });
			await makeUp.click();
			await expect(page.getByRole('region', { name: 'Proposed plan changes' })).toContainText(
				'Long run 14.0 km → 16.0 km',
				{ timeout: 15_000 }
			);
			await expect(page).toHaveURL(new RegExp(`/plans/${planId}$`));
			expect((await workout(ids.missed)).missed_ack_at).toBeNull();
		} finally {
			await page.context().close();
		}
	});

	test('Home: a missed easy run is let go, once, and the answer holds after a reload', async ({ browser }) => {
		const { ids } = await plantPlan([
			{ key: 'missed', offset: -2, kind: 'easy', distanceM: 6_000 },
			{ key: 'next', offset: 4, kind: 'long', distanceM: 14_000 }
		]);
		const page = await open(browser, '/dashboard');
		try {
			const prompt = page.getByTestId('missed-prompt');
			await expect(prompt.getByRole('heading')).toContainText('Missed: Easy on', { timeout: 15_000 });
			await expect(page.getByTestId('missed-prompt-body')).toHaveText(
				'Only a long run is worth making up. Let this one go rather than crowding it into the days ahead.'
			);
			await expect(page.getByTestId('missed-prompt-make-up')).toHaveCount(0);
			const letGo = page.getByTestId('missed-prompt-let-go');
			await expect(letGo).toContainText('Recommended');
			await letGo.click();
			await expect(page.getByText('Let go. Your plan carries on as it was.')).toBeVisible();
			await expect(prompt).toHaveCount(0);
			expect((await workout(ids.missed)).missed_ack_at).not.toBeNull();
			expect((await workout(ids.next)).target_distance_m).toBe(14_000);

			await page.reload();
			await expect(page.locator('.plan-hero')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('missed-prompt')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});

	test('at 300px the prompt wraps inside the plan hero instead of scrolling the page', async ({ browser }) => {
		await plantPlan(LONG_MISS);
		const context = await browser.newContext({
			storageState: runner.storageStatePath,
			viewport: { width: 300, height: 720 }
		});
		const page = await context.newPage();
		try {
			await page.goto('/dashboard');
			await expect(page.getByTestId('missed-prompt-make-up')).toBeVisible({ timeout: 15_000 });
			const { scrollWidth, clientWidth } = await page.evaluate(() => ({
				scrollWidth: document.documentElement.scrollWidth,
				clientWidth: document.documentElement.clientWidth
			}));
			expect(scrollWidth).toBeLessThanOrEqual(clientWidth);
		} finally {
			await context.close();
		}
	});

	test('a missed tempo is dropped, never offered as a make-up', async ({ browser }) => {
		const { planId } = await plantPlan([
			{ key: 'missed', offset: -1, kind: 'tempo', distanceM: 8_000 },
			{ key: 'next', offset: 4, kind: 'long', distanceM: 14_000 }
		]);
		const page = await open(browser, `/plans/${planId}`);
		try {
			await expect(page.getByTestId('missed-prompt').getByRole('heading')).toContainText('Missed: Tempo', {
				timeout: 15_000
			});
			await expect(page.getByTestId('missed-prompt-make-up')).toHaveCount(0);
			await expect(page.getByTestId('missed-prompt-let-go')).toContainText('Recommended');
		} finally {
			await page.context().close();
		}
	});

	test('a missed long run in the taper is let go', async ({ browser }) => {
		const { planId } = await plantPlan(
			[
				{ key: 'missed', offset: -3, kind: 'long', distanceM: 16_000 },
				{ key: 'next', offset: 4, kind: 'long', distanceM: 10_000 }
			],
			{ phases: { 1: 'taper', 2: 'taper' } }
		);
		const page = await open(browser, `/plans/${planId}`);
		try {
			await expect(page.getByTestId('missed-prompt-body')).toHaveText(
				"You're tapering, so let it go: being fresh on race day matters more than one more long run.",
				{ timeout: 15_000 }
			);
			await expect(page.getByTestId('missed-prompt-make-up')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});

	test('a miss answered on another device is not asked about on either page', async ({ browser }) => {
		const { planId } = await plantPlan([
			{ key: 'missed', offset: -2, kind: 'long', distanceM: 16_000, answered: true },
			{ key: 'next', offset: 4, kind: 'long', distanceM: 14_000 }
		]);
		const page = await open(browser, '/dashboard');
		try {
			await expect(page.locator('.plan-hero')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('missed-prompt')).toHaveCount(0);
			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e missed prompt' })).toBeVisible({
				timeout: 15_000
			});
			await expect(page.getByTestId('missed-prompt')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});

	test('a paused plan asks nothing', async ({ browser }) => {
		const { planId } = await plantPlan([{ key: 'missed', offset: -2, kind: 'easy', distanceM: 6_000 }], {
			status: 'paused'
		});
		const page = await open(browser, `/plans/${planId}`);
		try {
			await expect(page.getByRole('heading', { level: 1, name: 'e2e missed prompt' })).toBeVisible({
				timeout: 15_000
			});
			await expect(page.getByTestId('missed-prompt')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});

	test('a failed save says so, keeps the question and records nothing', async ({ browser }) => {
		const { planId, ids } = await plantPlan([{ key: 'missed', offset: -2, kind: 'easy', distanceM: 6_000 }]);
		const page = await open(browser, `/plans/${planId}`);
		try {
			await page.route('**/rest/v1/rpc/answer_missed_workouts', (route) =>
				route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' })
			);
			await page.getByTestId('missed-prompt-let-go').click({ timeout: 15_000 });
			await expect(page.getByText(/^Couldn't save your answer: /)).toBeVisible();
			await expect(page.getByTestId('missed-prompt')).toBeVisible();
			const row = await readMaybeRow(
				`workout ${ids.missed}`,
				getAdminClient().from('plan_workouts').select('missed_ack_at').eq('id', ids.missed).maybeSingle()
			);
			expect(row?.missed_ack_at).toBeNull();
		} finally {
			await page.context().close();
		}
	});
});
