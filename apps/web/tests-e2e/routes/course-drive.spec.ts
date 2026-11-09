import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { BLANK_TILE, FALLBACK_TILE_ORIGINS } from '../fixtures/map-tiles';
import { deleteRoute, insertRouteMarker } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /routes/[id] — Drive this course (issue #1310, docs/features/course_drive.md).
 *
 * The OSRM proxy is mocked in the browser: the leg's stops come back as the
 * routed line, with the ones between 37.515 and 37.525 pushed 350 m east, so
 * the check reports one stretch Maps can't follow.
 */

// Due north from 37.5,-77.45, one point every ~111 m: about 4.4 km.
const COURSE = Array.from({ length: 41 }, (_, i) => ({ lat: 37.5 + i * 0.001, lng: -77.45 }));

async function insertRoute(name: string, isPublic: boolean): Promise<string> {
	const { data, error } = await getAdminClient()
		.from('routes')
		.insert({
			user_id: USER_A.id,
			name,
			waypoints: COURSE,
			distance_m: 4_448,
			elevation_m: 0,
			is_public: isPublic,
		})
		.select('id')
		.single();
	if (error || !data) throw new Error(`route insert failed: ${error?.message}`);
	return data.id as string;
}

test.describe('/routes/[id] drive this course, as a non-owner', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('the Maps legs, the notes in course order and the stretch Maps cannot follow', async ({
		page,
		mockRoute,
	}) => {
		const routeId = await insertRoute(`Drive course ${Date.now()}`, true);
		await insertRouteMarker({
			route_id: routeId,
			user_id: USER_A.id,
			kind: 'hazard',
			label: 'Rail crossing',
			lat: 37.53,
			lng: -77.45,
		});
		await insertRouteMarker({
			route_id: routeId,
			user_id: USER_A.id,
			kind: 'aid_station',
			label: 'Aid 1',
			lat: 37.51,
			lng: -77.45,
			meta: { services: ['water', 'food'] },
		});
		try {
			await mockRoute(
				page,
				(url) => FALLBACK_TILE_ORIGINS.has(url.origin),
				(route) => route.fulfill({ status: 200, contentType: 'image/png', body: BLANK_TILE }),
			);
			await mockRoute(page, '**/api/routes/osrm/route/v1/car/**', (route) => {
				const coords = new URL(route.request().url()).pathname.split('/').pop()!;
				const routed = coords.split(';').map((pair) => {
					const [lng, lat] = pair.split(',').map(Number);
					return lat > 37.515 && lat < 37.525 ? [lng + 0.004, lat] : [lng, lat];
				});
				return route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ code: 'Ok', routes: [{ geometry: { type: 'LineString', coordinates: routed } }] }),
				});
			});

			await page.goto(`/routes/${routeId}`);
			const open = page.getByTestId('course-drive-open');
			await expect(open).toHaveText(/Drive this course/);
			await open.click();

			const dialog = page.getByTestId('course-drive-dialog');
			await expect(dialog).toBeVisible();
			await expect(dialog.getByTestId('course-drive-notice')).toContainText('passenger or a mounted phone');

			const legs = dialog.getByTestId('course-drive-legs').getByRole('link');
			await expect(legs).toHaveCount(1);
			const href = await legs.first().getAttribute('href');
			expect(href).toMatch(/^https:\/\/www\.google\.com\/maps\/dir\/\?api=1&destination=37\.54000%2C-77\.45000&waypoints=37\.50000%2C-77\.45000%7C/);
			expect(href).toContain('travelmode=driving');

			const notes = dialog.getByTestId('course-drive-notes').getByRole('listitem');
			await expect(notes).toHaveCount(2);
			await expect(notes.nth(0)).toContainText('Aid 1');
			await expect(notes.nth(0)).toContainText('Water, Food');
			await expect(notes.nth(1)).toContainText('Rail crossing');

			await expect(dialog.getByTestId('course-drive-check')).toHaveAttribute('data-state', 'done');
			await expect(dialog.getByTestId('course-drive-undrivable').getByRole('listitem')).toHaveCount(1);

			await dialog.getByLabel('Waze').check();
			await expect(legs.first()).toHaveAttribute('href', /^https:\/\/waze\.com\/ul\?ll=/);
			await expect(dialog.getByTestId('course-drive-start')).toHaveAttribute(
				'href',
				'https://waze.com/ul?ll=37.50000%2C-77.45000&navigate=yes',
			);
		} finally {
			await deleteRoute(routeId);
		}
	});
});

test.describe('/routes/[id] drive this course, as the owner', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a private route offers no drive mode, even to its owner', async ({ page, mockRoute }) => {
		const routeId = await insertRoute(`Private drive ${Date.now()}`, false);
		try {
			await mockRoute(
				page,
				(url) => FALLBACK_TILE_ORIGINS.has(url.origin),
				(route) => route.fulfill({ status: 200, contentType: 'image/png', body: BLANK_TILE }),
			);
			await page.goto(`/routes/${routeId}`);
			await expect(page.getByTestId('course-preview-open')).toBeVisible();
			await expect(page.getByTestId('course-drive-open')).toHaveCount(0);
		} finally {
			await deleteRoute(routeId);
		}
	});
});
