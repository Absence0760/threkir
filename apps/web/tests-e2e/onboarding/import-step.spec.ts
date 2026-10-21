import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';
import { getAdminClient } from '../fixtures/local-supabase';
import { readRow } from '../fixtures/db-read';
import type { MockRoute } from '../fixtures/mock-route';

/**
 * /onboarding — the "Bring your running history" step (issue #1190 § 6).
 *
 * The step builds no importer: each row saves the wizard's answers, stamps
 * onboarded_at, and lands on the import surface that already exists for that
 * source. It has to finish setup first, because the layout gate sends an
 * account with no onboarded_at back to /onboarding from every other page.
 * Skipping it is the one forward button.
 *
 * Borrows USER_A with onboarded_at nulled, and restores every row the wizard
 * can write in afterEach, the same way wizard.spec.ts does.
 */

const PARKRUN_PROBE = '**/functions/v1/parkrun-import';

/** Answer the parkrun probe the step runs, so the test decides the gate. */
async function parkrunProbe(page: Page, mockRoute: MockRoute, available: boolean): Promise<void> {
	await mockRoute(page, PARKRUN_PROBE, (route) =>
		available
			? route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: '{"ok":true}',
				})
			: route.fulfill({
					status: 404,
					contentType: 'application/json',
					body: '{"error":"not found"}',
				}),
	);
}

/** Walk name → track with every step left at its default. */
async function walkToImport(page: Page, displayName: string): Promise<void> {
	await page.goto('/onboarding');
	await expect(page.getByRole('heading', { name: /What should we call you/i })).toBeVisible();
	await page.getByLabel('Display name').fill(displayName);
	// Name, units, goal, about, privacy, track: no push key, so no
	// notifications step (visibleOnboardingSteps).
	for (let i = 0; i < 6; i++) {
		await page.getByRole('button', { name: 'Continue' }).click();
	}
	await expect(page.getByRole('heading', { name: /Bring your running history/i })).toBeVisible();
}

test.describe('/onboarding import step', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let savedProfile: {
		display_name: string | null;
		preferred_unit: string | null;
		onboarded_at: string | null;
	} | null = null;
	let savedPrefs: Record<string, unknown> | null = null;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		const { data: prof } = await admin
			.from('user_profiles')
			.select('display_name, preferred_unit, onboarded_at')
			.eq('id', USER_A.id)
			.single();
		savedProfile = prof ?? null;
		const { data: settings } = await admin
			.from('user_settings')
			.select('prefs')
			.eq('user_id', USER_A.id)
			.maybeSingle();
		savedPrefs = (settings?.prefs as Record<string, unknown> | null) ?? null;
		await admin.from('user_profiles').update({ onboarded_at: null }).eq('id', USER_A.id);
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({
				onboarded_at: savedProfile?.onboarded_at ?? new Date().toISOString(),
				display_name: savedProfile?.display_name ?? null,
				preferred_unit: savedProfile?.preferred_unit ?? 'km',
			})
			.eq('id', USER_A.id);
		if (savedPrefs) {
			await admin.from('user_settings').update({ prefs: savedPrefs }).eq('user_id', USER_A.id);
		}
	});

	test('sits between track and done, in the rail and the count', async ({ page, mockRoute }) => {
		await parkrunProbe(page, mockRoute, false);
		await page.setViewportSize({ width: 1440, height: 900 });
		await walkToImport(page, 'E2E Import Rail');
		await expect(page.getByRole('progressbar', { name: 'Step 7 of 8' })).toBeVisible();
		await expect(page.locator('.rail li.rail-now')).toHaveText(/History/);
		await expect(page.getByRole('heading', { name: /Bring your running history/i })).toBeFocused();
	});

	test('offers Strava and Garmin, no health platform, and parkrun only once its probe says yes', async ({
		page,
		mockRoute,
	}) => {
		await parkrunProbe(page, mockRoute, false);
		await walkToImport(page, 'E2E Import Sources');
		await expect(page.getByTestId('onboarding-import-strava')).toBeVisible();
		await expect(page.getByTestId('onboarding-import-garmin')).toBeVisible();
		await expect(page.getByTestId('onboarding-import-parkrun')).toHaveCount(0);
		// HealthKit and Health Connect have no web binding.
		await expect(page.getByText(/Apple Health|HealthKit|Health Connect/)).toHaveCount(0);
		await expect(
			page.getByRole('button', {
				name: /Strava.*Bring in your Strava activities/,
			}),
		).toBeVisible();
	});

	test('the parkrun row appears when the probe answers yes', async ({ page, mockRoute }) => {
		await parkrunProbe(page, mockRoute, true);
		await walkToImport(page, 'E2E Import Parkrun Shown');
		await expect(page.getByTestId('onboarding-import-parkrun')).toBeVisible();
	});

	test('Skip for now is one tap and onboarding still completes', async ({ page, mockRoute }) => {
		test.setTimeout(45_000);
		await parkrunProbe(page, mockRoute, false);
		await walkToImport(page, 'E2E Import Skipped');
		// One forward button, and it says what it does.
		await expect(page.getByRole('button', { name: 'Continue' })).toHaveCount(0);
		await page.getByRole('button', { name: 'Skip for now' }).click();
		await expect(page.getByRole('heading', { name: /All set/i })).toBeVisible();
		await page.getByRole('button', { name: 'Open dashboard' }).click();
		await page.waitForURL(/\/dashboard/, { timeout: 20_000 });

		const profile = await readRow(
			'user_profiles by id',
			getAdminClient()
				.from('user_profiles')
				.select('display_name, onboarded_at')
				.eq('id', USER_A.id)
				.single(),
		);
		expect(profile.onboarded_at).not.toBeNull();
		expect(profile.display_name).toBe('E2E Import Skipped');
	});

	for (const { source, url, heading } of [
		{
			source: 'strava',
			url: /\/settings\/integrations$/,
			heading: /Bulk import from a Strava export/i,
		},
		{
			source: 'garmin',
			url: /\/settings\/integrations$/,
			heading: /Bulk import from a Garmin export/i,
		},
		{ source: 'parkrun', url: /\/settings\/account$/, heading: null },
	] as const) {
		test(`the ${source} row saves setup and lands on its existing import surface`, async ({
			page,
			mockRoute,
		}) => {
			test.setTimeout(45_000);
			await parkrunProbe(page, mockRoute, true);
			const name = `E2E Import ${source}`;
			await walkToImport(page, name);
			await page.getByTestId(`onboarding-import-${source}`).click();
			await page.waitForURL(url, { timeout: 20_000 });

			// Setup was finished on the way, so the gate lets the import page
			// stay rather than bouncing back to the wizard.
			const profile = await readRow(
				'user_profiles by id',
				getAdminClient()
					.from('user_profiles')
					.select('display_name, onboarded_at')
					.eq('id', USER_A.id)
					.single(),
			);
			expect(profile.onboarded_at).not.toBeNull();
			expect(profile.display_name).toBe(name);
			if (heading) {
				await expect(page.getByRole('heading', { name: heading })).toBeVisible();
			} else {
				await expect(page.getByTestId('parkrun-number')).toBeVisible();
			}
			await expect(page).toHaveURL(url);
		});
	}
});
