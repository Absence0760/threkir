import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRoute, insertRoute, setUserSetting } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /routes — a route card's elevation reads in the runner's unit. The card
 * used to interpolate the raw metre figure into a string that said "m", so an
 * imperial runner saw "229 m" beside a distance in miles. 229 m is 751.3 ft,
 * so the imperial card must say "751 ft" and never "229 m".
 */
test.describe('/routes — card elevation honours the unit pref', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let routeId = '';
	let name = '';

	async function setUnit(unit: 'km' | 'mi') {
		await setUserSetting(USER_A.id, 'preferred_unit', unit);
		await getAdminClient()
			.from('user_profiles')
			.update({ preferred_unit: unit })
			.eq('id', USER_A.id);
	}

	test.beforeEach(async () => {
		name = `Elevation card ${Date.now()}`;
		routeId = await insertRoute({
			user_id: USER_A.id,
			name,
			waypoints: [
				{ lat: 51.5, lng: -0.12 },
				{ lat: 51.51, lng: -0.12 },
			],
			distance_m: 5_000,
			elevation_m: 229,
		});
	});

	test.afterEach(async () => {
		await deleteRoute(routeId);
		await setUnit('km');
	});

	async function card(page: import('@playwright/test').Page) {
		await page.goto('/routes');
		await page.getByLabel('Search routes').fill(name);
		const row = page.locator('.route-card', { hasText: name });
		await expect(row).toHaveCount(1, { timeout: 15_000 });
		return row.locator('.route-meta');
	}

	test('mi-mode: 229 m reads "751 ft"', async ({ page }) => {
		await setUnit('mi');
		const meta = await card(page);
		await expect(meta).toContainText('751 ft');
		await expect(meta).not.toContainText('229 m');
	});

	test('km-mode: 229 m reads "229 m"', async ({ page }) => {
		await setUnit('km');
		const meta = await card(page);
		await expect(meta).toContainText('229 m');
		await expect(meta).not.toContainText('ft');
	});
});
