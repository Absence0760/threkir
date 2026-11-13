import { expect, test } from '../fixtures/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { acceptCookieConsent } from '../fixtures/helpers';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { readRows } from '../fixtures/db-read';

/**
 * Heart rate and the food log are kept only with health-data consent
 * (decisions § 2514). A fresh saga user has none, as a real signup does.
 *
 *   1. /nutrition says why nothing can be logged, and the Log food dialog
 *      shows the same notice instead of the composer. A food_log insert in
 *      the runner's own session is refused by the database.
 *   2. A Strava ZIP whose row carries an average heart rate imports the run
 *      without it: the integrations page shows the notice with the consent
 *      link, and the stored row has no avg_bpm.
 *   3. With consent stamped, the notice is gone and the next import keeps
 *      the heart rate.
 */

function stravaActivityDate(d: Date): string {
	const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
	let hour = d.getUTCHours();
	const ampm = hour >= 12 ? 'PM' : 'AM';
	hour = hour % 12;
	if (hour === 0) hour = 12;
	const mm = String(d.getUTCMinutes()).padStart(2, '0');
	const ss = String(d.getUTCSeconds()).padStart(2, '0');
	return `${months[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}, ${hour}:${mm}:${ss} ${ampm}`;
}

async function zipWithHeartRate(stravaId: string, when: Date): Promise<Buffer> {
	const JSZip = (await import('jszip')).default;
	const zip = new JSZip();
	zip.file(
		'activities.csv',
		[
			'Activity ID,Activity Date,Activity Name,Activity Type,Filename,Distance,Moving Time,Elevation Gain,Average Heart Rate',
			`${stravaId},"${stravaActivityDate(when)}","HR run ${stravaId}",Run,,5.00,1500,42,151`,
			'',
		].join('\n'),
	);
	return Buffer.from(await zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE' }));
}

const newStravaId = () => `${Date.now()}${Math.floor(Math.random() * 100000)}`;

test.describe('heart rate and the food log need health-data consent', () => {
	let saga: SagaUser;

	test.beforeAll(async () => {
		[saga] = await createSagaUsers(1, { displayNames: ['Consent Gate'] });
	});

	test.afterAll(async () => {
		if (saga) await deleteSagaUsers([saga]);
	});

	test('food is refused and heart rate dropped until consent is given', async ({ browser }) => {
		const admin = getAdminClient();
		const ctx = await browser.newContext({ storageState: saga.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();

		await test.step('the food log says why nothing can be logged', async () => {
			await page.goto('/nutrition');
			await expect(page.getByTestId('food-consent-notice').first()).toBeVisible({ timeout: 10_000 });
			await expect(
				page.getByTestId('food-consent-notice').first().getByRole('link'),
			).toHaveAttribute('href', '/settings/account#setting-settingsAccount-healthConsentLabel');
			await page.getByTestId('log-food').click();
			const dialog = page.getByRole('dialog');
			await expect(dialog.getByTestId('food-consent-notice')).toBeVisible();
			await expect(dialog.locator('input')).toHaveCount(0);
		});

		await test.step('the database refuses a food_log insert from the runner', async () => {
			const asRunner = await getUserClient({ email: saga.email, password: saga.password });
			const { error } = await asRunner
				.from('food_log')
				.insert({ user_id: saga.id, item_name: 'Toast' });
			const status = error?.code ?? 'ok';
			expect(status).toBe('42501');
		});

		const firstId = newStravaId();
		await test.step('an import keeps the run and drops its heart rate', async () => {
			await page.goto('/settings/integrations');
			const card = page
				.locator('section.bulk-import')
				.filter({ hasText: 'Bulk import from a Strava export' });
			await expect(card).toBeVisible({ timeout: 10_000 });
			await card.locator('input[type="file"]').setInputFiles({
				name: 'strava_export.zip',
				mimeType: 'application/zip',
				buffer: await zipWithHeartRate(firstId, new Date()),
			});
			await expect(page.getByTestId('strava-zip-hr-dropped')).toBeVisible({ timeout: 15_000 });
			const rows = await readRows(
				'imported run without consent',
				admin.from('runs').select('metadata').eq('user_id', saga.id).eq('external_id', `strava:${firstId}`),
			);
			expect(rows).toHaveLength(1);
			expect((rows[0].metadata as Record<string, unknown>).avg_bpm).toBeUndefined();
		});

		await test.step('with consent the notice is gone and heart rate is kept', async () => {
			const { error } = await admin
				.from('user_profiles')
				.update({ health_data_consent_at: new Date().toISOString() })
				.eq('id', saga.id);
			if (error) throw new Error(`consent stamp failed: ${error.message}`);

			await page.goto('/nutrition');
			await expect(page.getByTestId('log-food')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('food-consent-notice')).toHaveCount(0);

			const secondId = newStravaId();
			await page.goto('/settings/integrations');
			const card = page
				.locator('section.bulk-import')
				.filter({ hasText: 'Bulk import from a Strava export' });
			await card.locator('input[type="file"]').setInputFiles({
				name: 'strava_export.zip',
				mimeType: 'application/zip',
				buffer: await zipWithHeartRate(secondId, new Date(Date.now() - 3_600_000)),
			});
			await expect(page.locator('.toast-success')).toContainText(/1 new/i, { timeout: 15_000 });
			await expect(page.getByTestId('strava-zip-hr-dropped')).toHaveCount(0);
			const rows = await readRows(
				'imported run with consent',
				admin.from('runs').select('metadata').eq('user_id', saga.id).eq('external_id', `strava:${secondId}`),
			);
			expect((rows[0].metadata as Record<string, unknown>).avg_bpm).toBe(151);
		});

		await ctx.close();
	});
});
