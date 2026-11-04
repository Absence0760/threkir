import type { Page, Request } from '@playwright/test';

import { expect, test } from '../fixtures/test';
import type { MockRoute } from '../fixtures/mock-route';

import { acceptCookieConsent } from '../fixtures/helpers';
import { BLANK_TILE, FALLBACK_TILE_ORIGINS } from '../fixtures/map-tiles';
import { RUNNER_PUBLIC_ROUTE_ID, RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';

/**
 * The share pages' maps wait for a per-view tap, banner or no banner.
 *
 * The cookie banner covers error reporting only; MapTiler logs the requester
 * IP on every tile fetch, so a logged-out visitor on /share/run/[id] or
 * /share/route/[id] taps "Load map" (2D) or "Load preview" (3D) on each view
 * (decisions § 2298 amendment). An accepted banner used to flip RunMap's
 * state inside onMount and call initMap before the map container existed:
 * the "Load map" card vanished and the map never drew.
 */

const TRACK = [
	{ lat: -37.82, lng: 144.97, ele: 20 },
	{ lat: -37.818, lng: 144.972, ele: 25 },
	{ lat: -37.816, lng: 144.974, ele: 30 },
	{ lat: -37.814, lng: 144.976, ele: 35 }
];

const isTileHost = (url: URL) =>
	FALLBACK_TILE_ORIGINS.has(url.origin) ||
	url.hostname === 'maptiler.com' ||
	url.hostname.endsWith('.maptiler.com');

/** Records every request that reaches a tile host. */
function watchTiles(page: Page): Request[] {
	const requests: Request[] = [];
	page.on('request', (req) => {
		if (isTileHost(new URL(req.url()))) requests.push(req);
	});
	return requests;
}

async function stubTiles(page: Page, mockRoute: MockRoute): Promise<void> {
	await mockRoute(page, isTileHost, (route) =>
		route.fulfill({ status: 200, contentType: 'image/png', body: BLANK_TILE })
	);
}

async function stubClippedTrack(page: Page, mockRoute: MockRoute): Promise<void> {
	await mockRoute(page, '**/functions/v1/clip-public-track', (route) =>
		route.fulfill({
			status: 200,
			contentType: 'application/json',
			body: JSON.stringify({ points: TRACK })
		})
	);
}

const SHARE_PAGES = [
	{ name: '/share/route/[id]', path: `/share/route/${RUNNER_PUBLIC_ROUTE_ID}`, clipped: false },
	{ name: '/share/run/[id]', path: `/share/run/${RUNNER_PUBLIC_RUN_ID}`, clipped: true }
];

for (const banner of ['accepted', 'not accepted'] as const) {
	test.describe(`share-page maps — logged out, banner ${banner}`, () => {
		test.use({ storageState: { cookies: [], origins: [] } });

		test.beforeEach(async ({ context }) => {
			if (banner === 'accepted') await acceptCookieConsent(context);
		});

		for (const share of SHARE_PAGES) {
			test(`${share.name}: the 2D map waits for Load map, then draws`, async ({ page, mockRoute }) => {
				// The run page's track comes from the clip Edge Function, which
				// reads Storage the seed does not fill; the route page's is the
				// seeded waypoints.
				if (share.clipped) await stubClippedTrack(page, mockRoute);
				await stubTiles(page, mockRoute);
				const tiles = watchTiles(page);
				await page.goto(share.path);

				const region = page.getByRole('region', { name: 'Run map' });
				const load = region.getByRole('button', { name: 'Load map' });
				await expect(load).toBeVisible({ timeout: 15_000 });
				await expect(region.getByText('MapTiler', { exact: true })).toBeVisible();
				await expect(region.locator('.run-map')).toHaveCount(0);
				expect(tiles, 'no tile host may be reached before the tap').toHaveLength(0);

				await load.click();
				await expect(region.locator('.maplibregl-canvas')).toBeVisible({ timeout: 15_000 });
				await expect(load).toHaveCount(0);
				await expect.poll(() => tiles.length, { timeout: 15_000 }).toBeGreaterThan(0);
			});
		}

		test('/share/route/[id]: the 3D preview names MapTiler and waits for Load preview', async ({
			page
		}) => {
			const tiles = watchTiles(page);
			await page.goto(`/share/route/${RUNNER_PUBLIC_ROUTE_ID}`);

			await page.getByRole('button', { name: 'Preview in 3D' }).click();
			const dialog = page.getByRole('dialog');
			await expect(dialog.getByRole('heading', { name: 'Load the 3D preview?' })).toBeVisible();
			await expect(dialog).toContainText('terrain tiles from MapTiler');
			await expect(dialog.getByRole('button', { name: 'Load preview' })).toBeVisible();
			expect(tiles, 'no tile host may be reached before the tap').toHaveLength(0);
		});
	});
}
