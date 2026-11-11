import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { deleteRaceListing, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * UltraSignup is a race LISTING source only. Its results leg read UltraSignup's
 * internal name-keyed feed and was removed with the other scrapers, so an
 * UltraSignup race offers manual paste alone — exactly like a manual or
 * RaceResult listing — and Settings has no UltraSignup card at all.
 */

test.describe('UltraSignup listing (no results leg)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const stamp = Date.now();
	const raceName = `E2E UltraSignup Listing ${stamp}`;
	let listingId: string | null = null;

	test.beforeAll(async () => {
		listingId = await insertRaceListing({
			provider: 'ultrasignup',
			name: raceName,
			race_date: browserDate(0),
			provider_race_id: 'e2e-ultrasignup-1'
		});
	});

	test.afterAll(async () => {
		if (listingId) await deleteRaceListing(listingId);
	});

	test('the settings page offers no UltraSignup card', async ({ page }) => {
		await page.goto('/settings/integrations');
		await expect(page.getByTestId('integration-strava')).toBeVisible({ timeout: 10_000 });

		await expect(page.getByTestId('ultrasignup-card')).toHaveCount(0);
		await expect(page.getByTestId('ultrasignup-open')).toHaveCount(0);
	});

	test('the race calendar import modal offers paste only', async ({ page }) => {
		await page.goto('/races');
		await page.getByTestId('races-search').fill(raceName);

		const card = page.getByTestId('race-card').filter({ hasText: raceName });
		await expect(card).toBeVisible({ timeout: 15_000 });
		await card.getByTestId('race-import').click();

		await expect(page.getByTestId('paste-save')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('race-ultrasignup-unavailable')).toHaveCount(0);
		await expect(page.getByTestId('race-import-ultrasignup')).toHaveCount(0);
		await expect(page.getByTestId('race-runsignup-unavailable')).toHaveCount(0);
	});
});
