import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { setStorageOnLoad } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { BLANK_TILE, FALLBACK_TILE_ORIGINS } from '../fixtures/map-tiles';
import { deleteRoute, insertRouteMarker } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /routes/[id] — the "Preview in 3D" entry point and the dialog behind it
 * (issue #1270).
 *
 * Headless Chromium may or may not have WebGL2, so no case asserts pixels or a
 * flight. The flat-fallback case pins the device to two cores, which
 * `flyoverMode` reads as a slow device whatever the GPU; the reduced-motion
 * case asks the browser which mode it should get and asserts that one.
 */

const AWS_TERRAIN_HOST = 'elevation-tiles-prod.s3.amazonaws.com';

const COURSE = [
	{ lat: 39.72, lng: -105.0, ele: 1600 },
	{ lat: 39.73, lng: -105.0, ele: 1630 },
	{ lat: 39.74, lng: -105.0, ele: 1660 },
	{ lat: 39.75, lng: -105.0, ele: 1650 },
];

async function insertRouteWith(
	name: string,
	waypoints: { lat: number; lng: number; ele?: number }[],
): Promise<string> {
	const { data, error } = await getAdminClient()
		.from('routes')
		.insert({
			user_id: USER_A.id,
			name,
			waypoints,
			distance_m: 3_300,
			elevation_m: 60,
			is_public: false,
		})
		.select('id')
		.single();
	if (error || !data) throw new Error(`route insert failed: ${error?.message}`);
	return data.id as string;
}

async function browserHasWebgl2(page: Page): Promise<boolean> {
	return page.evaluate(() => document.createElement('canvas').getContext('webgl2') !== null);
}

test.describe('/routes/[id] 3D course preview', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a slow device gets the flat fallback, and Esc closes the dialog and returns focus', async ({
		page,
		mockRoute,
	}) => {
		await page.addInitScript(() => {
			Object.defineProperty(Navigator.prototype, 'hardwareConcurrency', { get: () => 2 });
		});
		await mockRoute(
			page,
			(url) => FALLBACK_TILE_ORIGINS.has(url.origin),
			(route) => route.fulfill({ status: 200, contentType: 'image/png', body: BLANK_TILE }),
		);
		const routeId = await insertRouteWith(`3D preview ${Date.now()}`, COURSE);
		await insertRouteMarker({
			route_id: routeId,
			user_id: USER_A.id,
			kind: 'climb',
			label: 'Test Hill',
			lat: 39.73,
			lng: -105.0,
		});
		try {
			await page.goto(`/routes/${routeId}`);
			const open = page.getByTestId('course-preview-open');
			await expect(open).toHaveText(/Preview in 3D/);
			await open.click();

			const dialog = page.getByTestId('course-preview-3d');
			await expect(dialog).toBeVisible();
			await expect(dialog.locator('[data-flyover-mode]')).toHaveAttribute(
				'data-flyover-mode',
				'flat2d',
			);
			await expect(dialog.getByText(/shown on a flat map/)).toBeVisible();
			await expect(dialog.getByTestId('course-preview-play')).toHaveCount(0);
			await expect(dialog.getByTestId('course-preview-strip')).toBeVisible();

			await page.keyboard.press('Escape');
			await expect(dialog).toBeHidden();
			await expect(open).toBeFocused();
		} finally {
			await deleteRoute(routeId);
		}
	});

	test('without consent the dialog asks first; under reduced motion it holds still and the scrubber moves the readout', async ({
		page,
		mockRoute,
	}) => {
		await setStorageOnLoad(page, { consent: 'rejected' });
		await page.emulateMedia({ reducedMotion: 'reduce' });
		await mockRoute(
			page,
			(url) => FALLBACK_TILE_ORIGINS.has(url.origin),
			(route) => route.fulfill({ status: 200, contentType: 'image/png', body: BLANK_TILE }),
		);
		const routeId = await insertRouteWith(`3D preview reduced ${Date.now()}`, COURSE);
		try {
			await page.goto(`/routes/${routeId}`);
			const webgl2 = await browserHasWebgl2(page);
			await mockRoute(
				page,
				(url) => url.hostname === AWS_TERRAIN_HOST,
				(route) => route.fulfill({ status: 404 }),
				webgl2 ? {} : { neverFires: 'without WebGL2 the preview is flat and loads no terrain' },
			);

			const open = page.getByTestId('course-preview-open');
			await open.click();
			const dialog = page.getByTestId('course-preview-3d');
			await expect(dialog).toBeVisible();

			const load = dialog.getByTestId('course-preview-load');
			await expect(load).toBeVisible();
			await expect(dialog.getByTestId('course-preview-scrub')).toHaveCount(0);
			// The page's own map is behind the same consent, so the first tile
			// request (and, with WebGL2, the first terrain one) is the dialog's.
			const tiles = page.waitForRequest((r) => FALLBACK_TILE_ORIGINS.has(new URL(r.url()).origin));
			const terrain = webgl2
				? page.waitForRequest((r) => new URL(r.url()).hostname === AWS_TERRAIN_HOST)
				: null;
			await load.click();
			await tiles;
			await terrain;

			await expect(dialog.locator('[data-flyover-mode]')).toHaveAttribute(
				'data-flyover-mode',
				webgl2 ? 'static3d' : 'flat2d',
			);
			await expect(dialog.getByTestId('course-preview-play')).toHaveCount(0);

			const readout = dialog.getByTestId('course-preview-readout');
			const scrub = dialog.getByTestId('course-preview-scrub');
			await expect(readout).toContainText('0');
			const before = await readout.innerText();
			const max = Number(await scrub.getAttribute('max'));
			expect(max).toBeGreaterThan(3000);
			await scrub.fill(String(Math.round(max / 2)));
			await expect(readout).not.toHaveText(before);
			await expect(readout).toContainText(/1\.\d/);

			await page.keyboard.press('Escape');
			await expect(dialog).toBeHidden();
			await expect(open).toBeFocused();
		} finally {
			await deleteRoute(routeId);
		}
	});

	test('a route with no line to fly offers no preview', async ({ page }) => {
		const routeId = await insertRouteWith(`3D preview single point ${Date.now()}`, [COURSE[0]]);
		try {
			await page.goto(`/routes/${routeId}`);
			await expect(page.getByRole('heading', { name: /3D preview single point/ })).toBeVisible();
			await expect(page.getByTestId('course-preview-open')).toHaveCount(0);
		} finally {
			await deleteRoute(routeId);
		}
	});
});
