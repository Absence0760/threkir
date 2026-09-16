import { expect, test } from '@playwright/test';

import { browserDate } from '../fixtures/dates';
import { deleteRaceListing, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * RunSignUp fail-closed gate (race_calendar.md). With RUNSIGNUP_API_KEY unset
 * (the dev/CI default), the race-results-import probe returns 503
 * provider_not_configured, so the Settings → Integrations RunSignUp card shows
 * the unavailable explainer instead of an open-the-calendar action — and the
 * page does not crash. parkrun + manual paste stay available.
 */

test.describe('RunSignUp gate (unconfigured key)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const stamp = Date.now();
	const raceName = `E2E RunSignUp Gate ${stamp}`;
	const parkrunName = `E2E parkrun Gate ${stamp}`;
	let listingId: string | null = null;
	let parkrunListingId: string | null = null;

	test.beforeAll(async () => {
		listingId = await insertRaceListing({
			provider: 'runsignup',
			name: raceName,
			race_date: browserDate(30),
			provider_race_id: 'e2e-runsignup-1'
		});
		parkrunListingId = await insertRaceListing({
			provider: 'parkrun',
			name: parkrunName,
			race_date: browserDate(31),
			distance_m: 5000
		});
	});

	test.afterAll(async () => {
		if (listingId) await deleteRaceListing(listingId);
		if (parkrunListingId) await deleteRaceListing(parkrunListingId);
	});

	test('the settings card is not offered at all', async ({ page }) => {
		// The card used to render with an explainer where its action would be.
		// It is now filtered out of the page entirely: Settings offers what this
		// deployment can honour, and the explainer a runner actually needs lives
		// on the race whose result they are trying to import (asserted below).
		await page.goto('/settings/integrations');
		await expect(page.getByTestId('integration-parkrun')).toBeVisible({ timeout: 10_000 });

		await expect(page.getByTestId('runsignup-card')).toHaveCount(0);
		await expect(page.getByTestId('runsignup-open')).toHaveCount(0);
	});

	test('races import modal offers manual paste even when RunSignUp is gated', async ({ page }) => {
		await page.goto('/races');
		// The page loads without crashing despite the 503 probe.
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('race-submit')).toBeVisible();

		await page.getByTestId('races-search').fill(raceName);
		const card = page.getByTestId('race-card').filter({ hasText: raceName });
		await expect(card).toBeVisible({ timeout: 15_000 });
		await card.getByTestId('race-import').click();

		await expect(page.getByTestId('race-runsignup-unavailable')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('race-import-runsignup')).toHaveCount(0);
		await expect(page.getByTestId('runsignup-bib')).toHaveCount(0);
		await expect(page.getByTestId('paste-save')).toBeVisible();
	});

	test('a parkrun listing offers paste only — it has no bib-import leg', async ({ page }) => {
		// parkrun / manual / raceresult listings are not a gap in the gate: the
		// Edge Function has no leg for them, so falling through to the paste form
		// with no provider block at all is the correct answer.
		await page.goto('/races');
		await page.getByTestId('races-search').fill(parkrunName);

		const card = page.getByTestId('race-card').filter({ hasText: parkrunName });
		await expect(card).toBeVisible({ timeout: 15_000 });
		await card.getByTestId('race-import').click();

		await expect(page.getByTestId('paste-save')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('race-runsignup-unavailable')).toHaveCount(0);
		await expect(page.getByTestId('race-chronotrack-unavailable')).toHaveCount(0);
		await expect(page.getByTestId('race-ultrasignup-unavailable')).toHaveCount(0);
	});
});
