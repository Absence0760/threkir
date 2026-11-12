import { expect, test } from '../fixtures/test';

import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * The award division on the run's official result (decisions § 2086).
 *
 * A RunSignUp masters, overall or weight-class award lifts a runner out of
 * their age group, so `race-results-import` records it as its own pair of
 * owner-only keys. `RunRaceResult` renders it under its own label, and never
 * one half of the pair alone.
 */

test.describe('/runs/[id] — race division award', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const runs: string[] = [];

	test.afterEach(async () => {
		for (const id of runs.splice(0)) {
			try {
				await deleteRun(id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('a masters award renders as the award place, with no age-group row', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			duration_s: 3 * 3600 + 2 * 60 + 10,
			distance_m: 42_195,
			metadata: {
				race_name: 'E2E Award Marathon',
				chip_time: '3:02:10',
				overall_place: 9,
				division_award: 'M Masters',
				division_award_place: 2
			}
		});
		runs.push(runId);

		await page.goto(`/runs/${runId}`);
		const result = page.getByTestId('race-result');
		await expect(result).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('race-result-award')).toHaveText('2 (M Masters)');
		await expect(result).toContainText('Award place');
		await expect(result).not.toContainText('Age-group place');
	});

	test('an award label without its place draws no award row', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			duration_s: 1500,
			distance_m: 5000,
			metadata: {
				race_name: 'E2E Award 5K',
				chip_time: '25:00',
				division_award: 'F Top 3 Overall'
			}
		});
		runs.push(runId);

		await page.goto(`/runs/${runId}`);
		await expect(page.getByTestId('race-result')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('race-result-award')).toHaveCount(0);
	});
});
