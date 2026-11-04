import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRoute, setUserSetting } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /routes/[id] states one climb (issue #902).
 *
 * The header read the row's stored `elevation_m` while the Elevation tiles and
 * the chart's idle readout summed the waypoints. The waypoints are a simplified
 * (or, for a non-owner, privacy-clipped) line, so the same page read
 * `ELEVATION GAIN 320 m` and, 600 px below, `GAIN 100 m`. The shape planted
 * here is exactly that: 320 m stored over four waypoints that rise 100 m.
 */

async function setUnit(unit: 'km' | 'mi') {
	await setUserSetting(USER_A.id, 'preferred_unit', unit);
	await getAdminClient().from('user_profiles').update({ preferred_unit: unit }).eq('id', USER_A.id);
}

test.describe('/routes/[id] elevation', () => {
	test.use({ storageState: USER_A.storageStatePath });

	/**
	 * Every elevation on the page used to print raw metres with a literal "m"
	 * beside a distance in miles. 320 m is 1,049.9 ft, 220 m is 721.8 ft, and
	 * the extremes are 5,577 ft and 5,249 ft.
	 */
	test('an imperial runner reads every elevation in feet', async ({ page }) => {
		const { data, error } = await getAdminClient()
			.from('routes')
			.insert({
				user_id: USER_A.id,
				name: `Elevation imperial ${Date.now()}`,
				waypoints: [
					{ lat: 39.72, lng: -105.0, ele: 1600 },
					{ lat: 39.705, lng: -105.025, ele: 1640 },
					{ lat: 39.695, lng: -105.04, ele: 1680 },
					{ lat: 39.69, lng: -105.05, ele: 1700 }
				],
				distance_m: 42_000,
				elevation_m: 320,
				is_public: false
			})
			.select('id')
			.single();
		if (error || !data) throw new Error(`route insert failed: ${error?.message}`);
		const routeId = data.id as string;
		await setUnit('mi');
		try {
			await page.goto(`/routes/${routeId}`);
			await expect(page.getByTestId('route-key-gain')).toHaveText('1,050 ft');
			await expect(page.getByTestId('route-elev-gain')).toHaveText('1,050 ft');
			await expect(page.getByTestId('elevation-profile-total-gain')).toHaveText('1,050 ft');
			const tile = (label: string) =>
				page.locator('.elev-tile', { has: page.locator('.elev-label', { hasText: label }) });
			await expect(tile('Loss').locator('.elev-value')).toHaveText('722 ft');
			await expect(tile('Max').locator('.elev-value')).toHaveText('5,577 ft');
			await expect(tile('Min').locator('.elev-value')).toHaveText('5,249 ft');
		} finally {
			await setUnit('km');
			await deleteRoute(routeId);
		}
	});

	test('the header, the gain tile and the chart readout agree on the stored climb', async ({
		page
	}) => {
		const { data, error } = await getAdminClient()
			.from('routes')
			.insert({
				user_id: USER_A.id,
				name: `Elevation single source ${Date.now()}`,
				waypoints: [
					{ lat: 39.72, lng: -105.0, ele: 1600 },
					{ lat: 39.705, lng: -105.025, ele: 1640 },
					{ lat: 39.695, lng: -105.04, ele: 1680 },
					{ lat: 39.69, lng: -105.05, ele: 1700 }
				],
				distance_m: 42_000,
				elevation_m: 320,
				is_public: false
			})
			.select('id')
			.single();
		if (error || !data) throw new Error(`route insert failed: ${error?.message}`);
		const routeId = data.id as string;

		try {
			await page.goto(`/routes/${routeId}`);
			await expect(page.getByTestId('route-key-gain')).toHaveText('320 m');
			await expect(page.getByTestId('route-elev-gain')).toHaveText('320 m');
			await expect(page.getByTestId('elevation-profile-total-gain')).toHaveText('320 m');

			const tile = (label: string) =>
				page.locator('.elev-tile', { has: page.locator('.elev-label', { hasText: label }) });
			await expect(tile('Loss').locator('.elev-value')).toHaveText('220 m');
			await expect(tile('Max').locator('.elev-value')).toHaveText('1,700 m');
			await expect(tile('Min').locator('.elev-value')).toHaveText('1,600 m');
		} finally {
			await deleteRoute(routeId);
		}
	});
});
