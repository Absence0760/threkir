import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /settings/integrations — the provider cards, and the gate that decides
 * which of them this deployment is allowed to offer.
 *
 * The page renders only what it can honour (`integration_visibility.ts`):
 * Strava behind `PUBLIC_STRAVA_CLIENT_ID`, parkrun behind a reachability probe
 * of its Edge Function, Garmin Connect and Apple HealthKit never — the first
 * blocked on Garmin's developer programme, the second an on-device iOS API a
 * browser cannot reach. A card is also always shown while a row for it exists,
 * whatever the gate says, so a connection can still be disconnected.
 *
 * Local dev has no `PUBLIC_STRAVA_CLIENT_ID`, which is what makes the
 * unconfigured branch reachable from here at all.
 *
 * Future depth: Strava connect button click → mock OAuth flow, parkrun import
 * button against the seeded athlete number, Garmin .fit / .zip upload.
 */

test.describe('/settings/integrations', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the list offers what this deployment can honour, and nothing else', async ({
		page
	}) => {
		// Runner's seed has parkrun + strava connected (last_sync_at
		// populated), so both render whatever their gate says. Garmin Connect
		// and Apple HealthKit have no row and no leg, so neither is offered —
		// they used to render a live Connect button that wrote a placeholder
		// row and synced nothing.
		await page.goto('/settings/integrations');

		await expect(page.getByTestId('integration-strava')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('integration-parkrun')).toBeVisible();
		await expect(page.getByTestId('integration-garmin')).toHaveCount(0);
		await expect(page.getByTestId('integration-healthkit')).toHaveCount(0);
	});

	test('every offered card carries an info tip that explains the feature', async ({
		page
	}) => {
		// A new runner does not know what parkrun is, let alone what an athlete
		// number is for. The (i) is the only place on this page that says so.
		await page.goto('/settings/integrations');

		const trigger = page.getByTestId('info-parkrun');
		await expect(trigger).toBeVisible({ timeout: 10_000 });
		await expect(trigger).toHaveAttribute('aria-expanded', 'false');
		await expect(page.getByTestId('info-parkrun-panel')).toHaveCount(0);

		await trigger.click();
		const panel = page.getByTestId('info-parkrun-panel');
		await expect(panel).toBeVisible();
		await expect(panel).toContainText(/5k/i);
		await expect(trigger).toHaveAttribute('aria-expanded', 'true');

		// Escape closes it and puts focus back where the runner left it.
		await page.keyboard.press('Escape');
		await expect(panel).toHaveCount(0);
		await expect(trigger).toBeFocused();
	});

	test('the bulk importers are offered even when no provider can be connected', async ({
		page
	}) => {
		// They parse a file in the browser and need no credential and no Edge
		// Function, so they are the one path a minimal deployment always has.
		// Hiding them along with the account cards would leave a runner with no
		// way to get their history in at all.
		await page.goto('/settings/integrations');

		await expect(
			page.locator('section.bulk-import').filter({ hasText: 'Bulk import from a Strava export' })
		).toBeVisible({ timeout: 10_000 });
		await expect(
			page.locator('section.bulk-import').filter({ hasText: 'Bulk import from a Garmin export' })
		).toBeVisible();
	});

	test('parkrun connect → disconnect round-trip flips the button + the row class', async ({
		page
	}) => {
		// parkrun + garmin both go through the placeholder-connect path
		// (`connectIntegration(provider)` upsert into integrations) —
		// only Strava has live OAuth. parkrun starts connected per
		// seed, so the round-trip is Disconnect → Connect → Disconnect.
		// Tests the data-layer upsert + delete path that the canonical
		// click handler funnels into.
		await page.goto('/settings/integrations');

		const parkrunCard = page.locator('.integration-card', { hasText: 'parkrun' });
		await expect(parkrunCard).toBeVisible({ timeout: 10_000 });
		await expect(parkrunCard).toHaveClass(/connected/);

		await parkrunCard.getByRole('button', { name: 'Disconnect' }).click();
		const confirm = page.locator('.modal', { hasText: 'Disconnect integration?' });
		await expect(confirm).toBeVisible({ timeout: 5_000 });
		await confirm.getByRole('button', { name: 'Disconnect' }).click();
		await expect(parkrunCard).not.toHaveClass(/connected/, { timeout: 5_000 });
		await expect(parkrunCard.getByRole('button', { name: 'Connect' }))
			.toBeVisible();

		// Reconnect to restore the seed state.
		await parkrunCard.getByRole('button', { name: 'Connect' }).click();
		await expect(parkrunCard).toHaveClass(/connected/, { timeout: 5_000 });
	});

	test('an unconfigured Strava with no connection is not offered at all', async ({
		page
	}) => {
		// This used to be the "Connect fires the OAuth path" test, and what it
		// actually asserted locally was the error toast that came back AFTER
		// the tap — the only disclosure an unconfigured build ever made. The
		// gate moves that disclosure ahead of the tap by not rendering the
		// card, so there is no button left to press and no toast to raise.
		const admin = getAdminClient();
		try {
			await admin
				.from('integrations')
				.delete()
				.eq('user_id', USER_A.id)
				.eq('provider', 'strava');

			await page.goto('/settings/integrations');
			// parkrun is the proof the page rendered rather than merely failing
			// to reach the assertion below.
			await expect(page.getByTestId('integration-parkrun')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('integration-strava')).toHaveCount(0);
		} finally {
			// Restore seed state — Strava connected with the seeded
			// last_sync_at so downstream tests asserting that row holds.
			await admin.from('integrations').upsert(
				{
					user_id: USER_A.id,
					provider: 'strava',
					last_sync_at: '2026-03-30T08:00:00Z'
				},
				{ onConflict: 'user_id,provider' }
			);
		}
	});

	test('connected integration shows a last-sync timestamp', async ({ page }) => {
		// Strava starts connected per seed with last_sync_at populated.
		// The card surfaces a "Last sync …" line so the user knows
		// data is fresh. Pin the presence of the label — exact
		// timestamp format depends on the formatter but the label
		// is stable.
		await page.goto('/settings/integrations');
		const stravaCard = page.locator('.integration-card', { hasText: 'Strava' });
		await expect(stravaCard).toHaveClass(/connected/, { timeout: 10_000 });
		await expect(stravaCard.getByText(/Last sync/i)).toBeVisible();
	});

	test('Sync now button visible on a connected Strava card', async ({ page }) => {
		// 'Sync now' is the canonical re-fetch affordance for a
		// connected Strava integration. A regression that hides it
		// would leave users without a manual refresh path.
		await page.goto('/settings/integrations');
		const stravaCard = page.locator('.integration-card', { hasText: 'Strava' });
		await expect(stravaCard.getByRole('button', { name: /Sync/i }))
			.toBeVisible({ timeout: 10_000 });
	});
});

test.describe('/settings/integrations — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor is auth-walled to /login', async ({ page }) => {
		// /settings/integrations is NOT in the publicPaths list, so an
		// anon user must be redirected to /login with a return_to.
		await page.goto('/settings/integrations');
		await page.waitForURL(/\/login(\?|$)/, { timeout: 10_000 });
	});
});
