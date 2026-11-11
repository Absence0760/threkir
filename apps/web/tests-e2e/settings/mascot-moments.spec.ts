import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * Grisnir waits in the opted-in "nothing yet" states and hops beside a run's
 * milestone, and the universal `show_mascot` takes him off both (#1364).
 *
 * A throwaway runner with no runs, so the runs list starts empty and the
 * first run inserted is the runner's first run.
 */

let runner: SagaUser;

test.beforeAll(async () => {
	[runner] = await createSagaUsers(1, { displayNames: ['Mascot Moments Runner'] });
});

test.afterAll(async () => {
	await deleteSagaUsers([runner].filter(Boolean));
});

async function setShowMascot(value: boolean): Promise<void> {
	const { error } = await getAdminClient()
		.from('user_settings')
		.upsert({ user_id: runner.id, prefs: { show_mascot: value } });
	if (error) throw new Error(`show_mascot setup failed: ${error.message}`);
}

test('the empty runs list and the first run show him, and show_mascot off hides both', async ({ browser }) => {
	await setShowMascot(true);
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await context.newPage();
	try {
		await page.goto('/runs');
		const empty = page.getByTestId('runs-empty-no-data');
		await expect(empty).toBeVisible({ timeout: 15_000 });
		await expect(empty.getByTestId('empty-state-grisnir')).toBeVisible();
		await expect(empty.locator('img[alt=""]')).toHaveAttribute('aria-hidden', 'true');

		await setShowMascot(false);
		await page.reload();
		await expect(page.getByTestId('runs-empty-no-data')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('empty-state-grisnir')).toHaveCount(0);

		await setShowMascot(true);
		const runId = await insertRun({
			user_id: runner.id,
			started_at: '2026-05-10T08:00:00Z',
			distance_m: 3_000,
			duration_s: 1_100,
			metadata: { title: 'First mascot run' },
			track: Array.from({ length: 8 }, (_, i) => ({
				lat: -37.8 + i * 0.001,
				lng: 144.96 + (i % 2) * 0.0008,
				ts: new Date(Date.UTC(2026, 4, 10, 8, i)).toISOString(),
			})),
		});

		await page.goto(`/runs/${runId}`);
		const moment = page.getByTestId('run-milestone-grisnir');
		await expect(moment).toBeVisible({ timeout: 15_000 });
		await expect(moment).toHaveAttribute('data-milestone', 'first_run');
		await expect(moment).toContainText("First run in. That's the hard one.");

		await setShowMascot(false);
		await page.reload();
		await expect(page.locator('.detail-header')).toBeVisible({ timeout: 15_000 });
		// The settings read lands before the milestone reads; give both time
		// to settle before asserting he stayed away.
		await page.waitForLoadState('networkidle');
		await expect(page.getByTestId('run-milestone-grisnir')).toHaveCount(0);
	} finally {
		await context.close();
	}
});
