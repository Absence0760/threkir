import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRaceListing, deleteRun, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * The signed-in race detail page, /races/[id] (race_calendar.md).
 *
 * A calendar card's name opens it. Before race day the page offers training
 * and the race's own page but no import, and says when the import opens; the
 * calendar card hides the import the same way. From race day on the import is
 * offered, and a pasted result lands under "Your runs at this race" without a
 * reload. A listing that no longer exists reads as not found, not as an error.
 */

test.describe('/races/[id] — race detail', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const listings: string[] = [];

	test.afterEach(async () => {
		const runs = await readRows(
			'detail runs',
			getAdminClient()
				.from('runs')
				.select('id')
				.eq('user_id', USER_A.id)
				.in('race_listing_id', listings.length ? listings : ['00000000-0000-0000-0000-000000000000'])
		);
		for (const r of runs) {
			try {
				await deleteRun(r.id as string);
			} catch (_) {
				/* best-effort */
			}
		}
		for (const id of listings.splice(0)) {
			try {
				await deleteRaceListing(id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('a future race: the card opens it, it offers training and the race page, not an import', async ({
		page
	}) => {
		const raceName = `E2E Detail Future ${Date.now()}`;
		const entryUrl = 'https://runsignup.com/Race/UT/Moab/E2EDetailFuture';
		const id = await insertRaceListing({
			provider: 'runsignup',
			name: raceName,
			race_date: browserDate(60),
			distance_m: 42_195,
			entry_url: entryUrl
		});
		listings.push(id);

		await page.goto('/races');
		await page.getByTestId('races-search').fill(raceName);
		const card = page.getByTestId('race-card').filter({ hasText: raceName });
		await expect(card).toBeVisible({ timeout: 15_000 });
		await expect(card.getByTestId('race-import')).toHaveCount(0);
		await card.getByTestId('race-detail-link').click();

		await expect(page).toHaveURL(new RegExp(`/races/${id}$`));
		await expect(page.getByTestId('race-detail-name')).toHaveText(raceName);
		await expect(page.getByTestId('race-detail-source')).toHaveText('Listed on RunSignUp');
		await expect(page.getByTestId('race-detail-register')).toHaveAttribute('href', entryUrl);
		await expect(page.getByTestId('race-detail-register')).toHaveText('Race page & register');
		await expect(page.getByTestId('race-detail-train')).toBeVisible();
		await expect(page.getByTestId('race-detail-import')).toHaveCount(0);
		await expect(page.getByTestId('race-detail-import-later')).toBeVisible();
		await expect(page.getByTestId('race-detail-no-runs')).toBeVisible();

		await page.getByTestId('race-detail-back').click();
		await expect(page).toHaveURL(/\/races$/);
	});

	test('race day: a pasted result shows under your runs at this race', async ({ page }) => {
		const raceName = `E2E Detail Today ${Date.now()}`;
		const id = await insertRaceListing({
			provider: 'manual',
			name: raceName,
			race_date: browserDate(0),
			distance_m: 10_000
		});
		listings.push(id);

		await page.goto(`/races/${id}`);
		await expect(page.getByTestId('race-detail-name')).toHaveText(raceName, { timeout: 15_000 });
		await expect(page.getByTestId('race-detail-source')).toHaveText('Added by a runner');
		await expect(page.getByTestId('race-detail-import-later')).toHaveCount(0);
		await expect(page.getByTestId('race-detail-no-runs')).toBeVisible();

		await page.getByTestId('race-detail-import').click();
		await page.getByTestId('paste-bib').fill('7001');
		await page.getByTestId('paste-chip').fill('45:12');
		await page.getByTestId('paste-save').click();
		await expect(page.getByText('Official result imported.')).toBeVisible({ timeout: 15_000 });

		const runs = page.getByTestId('race-detail-runs');
		await expect(runs).toBeVisible({ timeout: 15_000 });
		await expect(runs).toContainText('45:12');
		await expect(page.getByTestId('race-detail-no-runs')).toHaveCount(0);
	});

	test('a listing that no longer exists reads as not found', async ({ page }) => {
		await page.goto('/races/00000000-0000-4000-8000-000000000000');
		await expect(page.getByTestId('race-detail-not-found')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('race-detail-error')).toHaveCount(0);
	});
});
