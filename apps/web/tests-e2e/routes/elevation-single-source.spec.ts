import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRoute } from '../fixtures/simulate';
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

test.describe('/routes/[id] elevation', () => {
	test.use({ storageState: USER_A.storageStatePath });

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
			await expect(tile('Max').locator('.elev-value')).toHaveText('1700 m');
			await expect(tile('Min').locator('.elev-value')).toHaveText('1600 m');
		} finally {
			await deleteRoute(routeId);
		}
	});
});
