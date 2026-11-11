import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { BLANK_TILE, FALLBACK_TILE_ORIGINS } from '../fixtures/map-tiles';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { clearUserSettingKey, deleteRoute, setUserSetting } from '../fixtures/simulate';

/**
 * Grisnir trots the line in the 3D course preview in place of the dot
 * (#1364): he mounts when the map is up, his GLB is fetched only then, the
 * runner's `show_mascot` off keeps the dot, and a GLB that fails to load
 * keeps the dot with nothing said to the runner.
 *
 * Headless Chromium may lack WebGL2, and then the dialog is flat and never
 * wants him, so each case skips without it. No case asserts pixels.
 *
 * Runs as a throwaway runner so the pref never reaches another spec's user.
 */

const AWS_TERRAIN_HOST = 'elevation-tiles-prod.s3.amazonaws.com';
const GLB_PATH = '/brand/grisnir/grisnir-trot.glb';

const COURSE = [
	{ lat: 39.72, lng: -105.0, ele: 1600 },
	{ lat: 39.73, lng: -105.0, ele: 1630 },
	{ lat: 39.74, lng: -105.01, ele: 1660 },
	{ lat: 39.75, lng: -105.01, ele: 1650 },
];

let runner: SagaUser;
let routeId: string;

test.beforeAll(async () => {
	[runner] = await createSagaUsers(1, { displayNames: ['Grisnir Preview Runner'] });
	const { data, error } = await getAdminClient()
		.from('routes')
		.insert({
			user_id: runner.id,
			name: `Grisnir preview ${Date.now()}`,
			waypoints: COURSE,
			distance_m: 3_400,
			elevation_m: 60,
			is_public: false,
		})
		.select('id')
		.single();
	if (error || !data) throw new Error(`route insert failed: ${error?.message}`);
	routeId = data.id as string;
});

test.afterAll(async () => {
	if (routeId) await deleteRoute(routeId);
	await deleteSagaUsers([runner].filter(Boolean));
});

test.afterEach(async () => {
	await clearUserSettingKey(runner.id, 'show_mascot');
});

async function openRoutePage(browser: Browser): Promise<Page> {
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	// The map waits on the banner's answer, and a fresh context has none: the
	// dialog would ask first and stay flat.
	await acceptCookieConsent(context);
	const page = await context.newPage();
	await page.addInitScript(() => {
		Object.defineProperty(Navigator.prototype, 'hardwareConcurrency', { get: () => 8 });
	});
	return page;
}

async function browserHasWebgl2(page: Page): Promise<boolean> {
	return page.evaluate(() => document.createElement('canvas').getContext('webgl2') !== null);
}

function glbRequested(page: Page): () => number {
	let n = 0;
	page.on('request', (r) => {
		if (new URL(r.url()).pathname === GLB_PATH) n++;
	});
	return () => n;
}

test('with the setting on he replaces the dot, and his GLB loads only when the dialog does', async ({
	browser,
	mockRoute,
}) => {
	const page = await openRoutePage(browser);
	try {
		await mockRoute(
			page,
			(url) => FALLBACK_TILE_ORIGINS.has(url.origin),
			(route) => route.fulfill({ status: 200, contentType: 'image/png', body: BLANK_TILE }),
		);
		const requests = glbRequested(page);
		await page.goto(`/routes/${routeId}`);
		test.skip(!(await browserHasWebgl2(page)), 'he needs WebGL2, as the 3D dialog does');
		await mockRoute(
			page,
			(url) => url.hostname === AWS_TERRAIN_HOST,
			(route) => route.fulfill({ status: 404 }),
		);
		await page.waitForLoadState('networkidle');
		expect(requests()).toBe(0);

		await page.getByTestId('course-preview-open').click();
		const dialog = page.getByTestId('course-preview-3d');
		const preview = dialog.locator('[data-flyover-mode]');
		await expect(preview).toHaveAttribute('data-flyover-mode', 'flight');
		await expect(preview).toHaveAttribute('data-position-marker', 'mascot', { timeout: 15_000 });
		const marker = dialog.getByTestId('course-preview-position');
		await expect(marker.locator('canvas')).toHaveCount(1);
		await expect(marker).toHaveClass(/course-preview-mascot/);
		expect(requests()).toBe(1);
		await expect(dialog.locator('.preview-note-error')).toHaveCount(0);
	} finally {
		await page.context().close();
	}
});

test('with show_mascot off the dialog keeps the dot and never fetches him', async ({ browser, mockRoute }) => {
	await setUserSetting(runner.id, 'show_mascot', false);
	const page = await openRoutePage(browser);
	try {
		await mockRoute(
			page,
			(url) => FALLBACK_TILE_ORIGINS.has(url.origin),
			(route) => route.fulfill({ status: 200, contentType: 'image/png', body: BLANK_TILE }),
		);
		const requests = glbRequested(page);
		await page.goto(`/routes/${routeId}`);
		test.skip(!(await browserHasWebgl2(page)), 'he needs WebGL2, as the 3D dialog does');
		await mockRoute(
			page,
			(url) => url.hostname === AWS_TERRAIN_HOST,
			(route) => route.fulfill({ status: 404 }),
		);
		// The map's first terrain request says it came up, so the dot below
		// is the setting's doing and not a map that never loaded.
		const terrain = page.waitForRequest((r) => new URL(r.url()).hostname === AWS_TERRAIN_HOST);
		await page.getByTestId('course-preview-open').click();
		await terrain;
		const dialog = page.getByTestId('course-preview-3d');
		const marker = dialog.getByTestId('course-preview-position');
		await expect(marker).toBeVisible();
		// The settings read is async; let it land before judging.
		await page.waitForLoadState('networkidle');
		await expect(dialog.locator('[data-flyover-mode]')).toHaveAttribute('data-position-marker', 'dot');
		await expect(marker).toHaveClass(/course-preview-position/);
		await expect(marker.locator('canvas')).toHaveCount(0);
		expect(requests()).toBe(0);
	} finally {
		await page.context().close();
	}
});

test('a GLB that fails to load keeps the dot and says nothing to the runner', async ({ browser, mockRoute }) => {
	const page = await openRoutePage(browser);
	try {
		await mockRoute(
			page,
			(url) => FALLBACK_TILE_ORIGINS.has(url.origin),
			(route) => route.fulfill({ status: 200, contentType: 'image/png', body: BLANK_TILE }),
		);
		await page.goto(`/routes/${routeId}`);
		const webgl2 = await browserHasWebgl2(page);
		await mockRoute(
			page,
			(url) => url.pathname === GLB_PATH,
			(route) => route.fulfill({ status: 404 }),
			webgl2 ? {} : { neverFires: 'without WebGL2 the dialog is flat and never wants him' },
		);
		test.skip(!webgl2, 'he needs WebGL2, as the 3D dialog does');
		await mockRoute(
			page,
			(url) => url.hostname === AWS_TERRAIN_HOST,
			(route) => route.fulfill({ status: 404 }),
		);
		const glbFailed = page.waitForResponse((r) => new URL(r.url()).pathname === GLB_PATH);
		await page.getByTestId('course-preview-open').click();
		const dialog = page.getByTestId('course-preview-3d');
		await glbFailed;
		const marker = dialog.getByTestId('course-preview-position');
		await expect(marker).toBeVisible();
		await expect(dialog.locator('[data-flyover-mode]')).toHaveAttribute('data-position-marker', 'dot');
		await expect(marker.locator('canvas')).toHaveCount(0);
		await expect(dialog.locator('.preview-note-error')).toHaveCount(0);
		await expect(dialog.getByTestId('course-preview-play')).toBeEnabled();
	} finally {
		await page.context().close();
	}
});
