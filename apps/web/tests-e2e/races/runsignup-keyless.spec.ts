import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { deleteRaceListing, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * RunSignUp needs no key (decisions § 1903). Its race and results feeds are
 * public, so the race-results-import probe answers `configured: true` on a
 * deployment with no RUNSIGNUP_API_KEY — the dev/CI default — and the Settings
 * card and the bib-scoped import are offered against the real local function.
 * The explainer survives for the one case left that reaches it: a probe that
 * fails, which both clients grade fail-closed as unavailable.
 */

test.describe('RunSignUp is keyless', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const stamp = Date.now();
	const raceName = `E2E RunSignUp Keyless ${stamp}`;
	const parkrunName = `E2E parkrun Keyless ${stamp}`;
	let listingId: string | null = null;
	let parkrunListingId: string | null = null;

	test.beforeAll(async () => {
		listingId = await insertRaceListing({
			provider: 'runsignup',
			name: raceName,
			race_date: browserDate(0),
			provider_race_id: 'e2e-runsignup-1'
		});
		parkrunListingId = await insertRaceListing({
			provider: 'parkrun',
			name: parkrunName,
			race_date: browserDate(0),
			distance_m: 5000
		});
	});

	test.afterAll(async () => {
		if (listingId) await deleteRaceListing(listingId);
		if (parkrunListingId) await deleteRaceListing(parkrunListingId);
	});

	test('the settings card is offered on a deployment with no RunSignUp key', async ({ page }) => {
		await page.goto('/settings/integrations');
		await expect(page.getByTestId('integration-parkrun')).toBeVisible({ timeout: 10_000 });

		await expect(page.getByTestId('runsignup-card')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('runsignup-open')).toHaveAttribute('href', '/races');
	});

	test('the import modal asks for the bib, beside manual paste', async ({ page }) => {
		await page.goto('/races');
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		await page.getByTestId('races-search').fill(raceName);
		const card = page.getByTestId('race-card').filter({ hasText: raceName });
		await expect(card).toBeVisible({ timeout: 15_000 });
		await card.getByTestId('race-import').click();

		await expect(page.getByTestId('runsignup-bib')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('race-import-runsignup')).toBeVisible();
		await expect(page.getByTestId('race-runsignup-unavailable')).toHaveCount(0);
		await expect(page.getByTestId('paste-save')).toBeVisible();
	});

	test('a probe that fails still reads as unavailable, and paste stays', async ({ page, mockRoute }) => {
		await mockRoute(page, '**/functions/v1/race-results-import', (route) =>
			route.fulfill({
				status: 503,
				contentType: 'application/json',
				body: JSON.stringify({ error: 'provider_not_configured' })
			})
		);
		await page.goto('/races');
		await page.getByTestId('races-search').fill(raceName);
		const card = page.getByTestId('race-card').filter({ hasText: raceName });
		await expect(card).toBeVisible({ timeout: 15_000 });
		await card.getByTestId('race-import').click();

		await expect(page.getByTestId('race-runsignup-unavailable')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('runsignup-bib')).toHaveCount(0);
		await expect(page.getByTestId('paste-save')).toBeVisible();
	});

	test('a parkrun listing offers paste only — it has no bib-import leg', async ({ page }) => {
		// parkrun / manual / raceresult listings are not a gap: the Edge Function
		// has no leg for them, so falling through to the paste form with no
		// provider block at all is the correct answer.
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
