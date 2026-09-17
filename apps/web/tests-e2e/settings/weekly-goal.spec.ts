import { expect, test, type Locator, type Page } from '@playwright/test';

import { readRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * The weekly distance goal is asked for in km or mi and stored in metres
 * (issue #902 § 5). The field used to read `Weekly Mileage Goal (m)` with
 * `50000` in it. What is pinned here is the boundary the unit test cannot
 * reach: what the runner types is the metres the bag receives, it reads back
 * in their own unit after a reload, and blurring a value nobody edited writes
 * back the metres that were already stored rather than the rounded display.
 */

const PAGE = '/settings/preferences';
const SEEDED_GOAL_M = 50000;

async function storedGoal(): Promise<unknown> {
	const row = await readRow(
		'user_settings for USER_A',
		getAdminClient().from('user_settings').select('prefs').eq('user_id', USER_A.id).single()
	);
	return (row.prefs as Record<string, unknown>).weekly_mileage_goal_m;
}

async function setStoredGoal(metres: number): Promise<void> {
	const admin = getAdminClient();
	const row = await readRow(
		'user_settings for USER_A',
		admin.from('user_settings').select('prefs').eq('user_id', USER_A.id).single()
	);
	const prefs = { ...(row.prefs as Record<string, unknown>), weekly_mileage_goal_m: metres };
	const { error } = await admin.from('user_settings').update({ prefs }).eq('user_id', USER_A.id);
	if (error) throw new Error(`setting USER_A's weekly goal failed: ${error.message}`);
}

async function pickUnit(page: Page, name: 'Miles' | 'Kilometres') {
	await page.getByRole('button', { name, exact: true }).click();
	await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });
}

async function blurAndAwaitGoalWrite(page: Page, field: Locator, metres: number) {
	const write = page.waitForRequest(
		(req) =>
			req.method() === 'POST' &&
			req.url().includes('/rest/v1/user_settings') &&
			(req.postData() ?? '').includes(`"weekly_mileage_goal_m":${metres}`),
		{ timeout: 8_000 }
	);
	await field.blur();
	await write;
	await expect.poll(storedGoal, { timeout: 5_000 }).toBe(metres);
}

test.describe('weekly distance goal', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		await setStoredGoal(SEEDED_GOAL_M);
	});

	test.afterEach(async ({ page }) => {
		await page.goto(PAGE);
		await pickUnit(page, 'Kilometres');
		await setStoredGoal(SEEDED_GOAL_M);
	});

	test('is typed in kilometres and stored in metres', async ({ page }) => {
		await page.goto(PAGE);
		await pickUnit(page, 'Kilometres');

		const goal = page.getByTestId('weekly-distance-goal');
		await expect(page.getByText('Weekly distance goal (km)', { exact: true })).toBeVisible();
		await expect(goal).toHaveValue('50');

		await goal.fill('42.2');
		await blurAndAwaitGoalWrite(page, goal, 42200);

		await page.reload();
		await expect(page.getByTestId('weekly-distance-goal')).toHaveValue('42.2');
	});

	test('reads in miles for a miles runner, and an untouched value does not drift', async ({
		page
	}) => {
		await page.goto(PAGE);
		await pickUnit(page, 'Miles');

		const goal = page.getByTestId('weekly-distance-goal');
		await expect(page.getByText('Weekly distance goal (mi)', { exact: true })).toBeVisible();
		await expect(goal).toHaveValue('31.1');

		await goal.focus();
		await blurAndAwaitGoalWrite(page, goal, SEEDED_GOAL_M);

		await goal.fill('26.2');
		await blurAndAwaitGoalWrite(page, goal, 42165);

		await page.reload();
		await expect(page.getByTestId('weekly-distance-goal')).toHaveValue('26.2');
	});

	test('a goal outside the range is refused in the field and not saved', async ({ page }) => {
		await page.goto(PAGE);
		await pickUnit(page, 'Kilometres');

		const goal = page.getByTestId('weekly-distance-goal');
		await goal.fill('600');
		await goal.blur();
		await expect(page.getByTestId('weekly-distance-goal-error')).toHaveText(
			'Enter a goal between 0.1 and 500 km.'
		);
		await expect(goal).toHaveAttribute('aria-invalid', 'true');

		// Edits on this page are coalesced into one write, so a refused goal
		// that had been queued anyway would ride out on the next save.
		const nextWrite = page.waitForRequest(
			(req) =>
				req.method() === 'POST' &&
				req.url().includes('/rest/v1/user_settings') &&
				(req.postData() ?? '').includes('"preferred_unit":"km"'),
			{ timeout: 8_000 }
		);
		await page.getByRole('button', { name: 'Kilometres', exact: true }).click();
		expect((await nextWrite).postData()).toContain(`"weekly_mileage_goal_m":${SEEDED_GOAL_M}`);
		await expect.poll(storedGoal, { timeout: 5_000 }).toBe(SEEDED_GOAL_M);
	});
});
