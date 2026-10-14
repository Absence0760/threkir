import { expect, test } from '@playwright/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRaceListing, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * A RunSignUp race reaches "near me" through its ZIP (decisions § 1901). The
 * feed carries no coordinates, so race-listings-sync looks the ZIP up in
 * `us_zcta_points` and writes the centroid as the listing's `location_point`;
 * `search_race_listings` then answers a geolocated search within its default
 * 50 km radius. The listings here are seeded the way the sync writes them —
 * provider `runsignup`, verified, the point read from the ZCTA table itself —
 * so a table that lost its rows, or a point in the wrong axis order, fails here.
 */

const NEAR_ZIP = '23219'; // Richmond, VA
const FAR_ZIP = '90012'; // Los Angeles, CA

async function zipPointEwkt(zip: string): Promise<string> {
	const { data, error } = await getAdminClient()
		.from('us_zcta_points')
		.select('lat, lng')
		.eq('zcta', zip)
		.single();
	if (error || !data) throw new Error(`no ZCTA point for ${zip}: ${error?.message}`);
	return `SRID=4326;POINT(${data.lng} ${data.lat})`;
}

function enGbDate(iso: string): string {
	return new Intl.DateTimeFormat('en-GB', {
		timeZone: 'UTC',
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	}).format(new Date(`${iso}T00:00:00Z`));
}

test.describe('/races — a zip-placed RunSignUp race shows near me', () => {
	test.use({
		storageState: USER_A.storageStatePath,
		permissions: ['geolocation'],
		// About 2 km from the 23219 centroid.
		geolocation: { latitude: 37.55, longitude: -77.45 }
	});

	const stamp = Date.now();
	const prefix = `E2E RSU Near ${stamp}`;
	const nearName = `${prefix} Richmond 10K`;
	const farName = `${prefix} Los Angeles 10K`;
	const nearDate = browserDate(40);
	const entryUrl = `https://runsignup.com/Race/VA/Richmond/E2E${stamp}`;
	const ids: string[] = [];

	test.beforeAll(async () => {
		ids.push(
			await insertRaceListing({
				provider: 'runsignup',
				provider_race_id: `e2e-near-${stamp}`,
				name: nearName,
				race_date: nearDate,
				distance_m: 10_000,
				location_label: 'Richmond, VA',
				entry_url: entryUrl,
				location_point: await zipPointEwkt(NEAR_ZIP)
			})
		);
		ids.push(
			await insertRaceListing({
				provider: 'runsignup',
				provider_race_id: `e2e-far-${stamp}`,
				name: farName,
				race_date: browserDate(41),
				distance_m: 10_000,
				location_label: 'Los Angeles, CA',
				entry_url: 'https://runsignup.com/Race/CA/LosAngeles/E2EFar',
				location_point: await zipPointEwkt(FAR_ZIP)
			})
		);
	});

	test.afterAll(async () => {
		for (const id of ids) await deleteRaceListing(id);
	});

	test('the nearby race is listed with its date and register link, the far one is not', async ({
		page
	}) => {
		await page.goto('/races');
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

		const results = page.getByTestId('races-results');
		const near = results.getByTestId('race-card').filter({ hasText: nearName });
		const far = results.getByTestId('race-card').filter({ hasText: farName });

		// Without a centre both are listed, so the near-me gate is what drops one.
		await page.getByTestId('races-search').fill(prefix);
		await expect(near).toBeVisible({ timeout: 15_000 });
		await expect(far).toBeVisible();

		await page.getByTestId('races-use-location').click();
		await expect(page.getByTestId('races-near-clear')).toBeVisible({ timeout: 10_000 });

		await expect(far).toBeHidden({ timeout: 15_000 });
		await expect(near).toBeVisible();
		await expect(near).toContainText(enGbDate(nearDate));
		await expect(near.getByTestId('race-away')).toBeVisible();
		await expect(near.getByTestId('race-register')).toHaveAttribute('href', entryUrl);
	});
});
