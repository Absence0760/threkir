import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { BLANK_TILE, FALLBACK_TILE_ORIGINS } from '../fixtures/map-tiles';
import { deleteRoute } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * The flyover video export in the 3D course preview (issue #1273 item 1,
 * decisions § 2259), on a keyless build: the export is never offered here,
 * because the only basemap is the OSM fallback. The case where it is offered,
 * renders and cancels is configured/course-preview-video.spec.ts. Which mode a headless browser gets depends on its GPU,
 * and whether it can encode depends on its build, so each case asks the
 * browser and asserts what that answer implies rather than skipping.
 */

const AWS_TERRAIN_HOST = 'elevation-tiles-prod.s3.amazonaws.com';

const COURSE = [
	{ lat: 39.72, lng: -105.0, ele: 1600 },
	{ lat: 39.725, lng: -105.0, ele: 1630 },
	{ lat: 39.73, lng: -105.0, ele: 1660 },
	{ lat: 39.735, lng: -105.0, ele: 1650 },
];

async function insertPublicRoute(name: string): Promise<string> {
	const { data, error } = await getAdminClient()
		.from('routes')
		.insert({
			user_id: USER_A.id,
			name,
			waypoints: COURSE,
			distance_m: 1_700,
			elevation_m: 60,
			is_public: true,
		})
		.select('id')
		.single();
	if (error || !data) throw new Error(`route insert failed: ${error?.message}`);
	return data.id as string;
}

/// Whether this browser takes the 3D path (WebGL2) and has an encoder the
/// export can use: WebCodecs H.264 or a canvas stream for MediaRecorder.
async function exportCapable(page: Page): Promise<{ webgl2: boolean; encoder: boolean }> {
	return page.evaluate(async () => {
		const webgl2 = document.createElement('canvas').getContext('webgl2') !== null;
		let encoder = false;
		if (typeof VideoEncoder !== 'undefined') {
			for (const codec of ['avc1.640028', 'avc1.4d0028', 'avc1.42e028']) {
				try {
					const r = await VideoEncoder.isConfigSupported({ codec, width: 1080, height: 1920, bitrate: 8e6, framerate: 30 });
					if (r.supported) encoder = true;
				} catch {
					// unknown codec string
				}
			}
		}
		if (!encoder && typeof MediaRecorder !== 'undefined') {
			encoder = ['video/mp4', 'video/webm'].some((t) => MediaRecorder.isTypeSupported(t));
		}
		return { webgl2, encoder };
	});
}

test.describe('/routes/[id] flyover video export', () => {
	test.describe('as another runner', () => {
		test.use({ storageState: USER_B.storageStatePath });

		test('a slow device gets the flat map and no export', async ({ page, mockRoute }) => {
			await page.addInitScript(() => {
				Object.defineProperty(Navigator.prototype, 'hardwareConcurrency', { get: () => 2 });
			});
			await mockRoute(
				page,
				(url) => FALLBACK_TILE_ORIGINS.has(url.origin),
				(route) => route.fulfill({ status: 200, contentType: 'image/png', body: BLANK_TILE }),
			);
			const routeId = await insertPublicRoute(`Video flat ${Date.now()}`);
			try {
				await page.goto(`/routes/${routeId}`);
				await page.getByTestId('course-preview-open').click();
				const dialog = page.getByTestId('course-preview-3d');
				await expect(dialog.locator('[data-flyover-mode]')).toHaveAttribute('data-flyover-mode', 'flat2d');
				await expect(dialog.getByTestId('course-preview-strip')).toBeVisible();
				await expect(dialog.getByTestId('course-preview-export-video')).toHaveCount(0);
			} finally {
				await deleteRoute(routeId);
			}
		});

		test('with no basemap a video may record, a capable browser is offered no export', async ({ page, mockRoute }) => {
			// This lane builds like a keyless deploy: no MapTiler key and no
			// tile-style override, so the only basemap is the OSM raster
			// fallback, which a video export must not bulk-render (decisions
			// § 2259). The offered case runs in the configured lane, which sets
			// the override.
			await page.emulateMedia({ reducedMotion: 'reduce' });
			await mockRoute(
				page,
				(url) => FALLBACK_TILE_ORIGINS.has(url.origin),
				(route) => route.fulfill({ status: 200, contentType: 'image/png', body: BLANK_TILE }),
			);
			const routeId = await insertPublicRoute(`Video keyless ${Date.now()}`);
			try {
				await page.goto(`/routes/${routeId}`);
				const { webgl2 } = await exportCapable(page);
				await mockRoute(
					page,
					(url) => url.hostname === AWS_TERRAIN_HOST,
					(route) => route.fulfill({ status: 404 }),
					webgl2 ? {} : { neverFires: 'without WebGL2 the preview is flat and loads no terrain' },
				);
				const terrain = webgl2 ? page.waitForRequest((r) => new URL(r.url()).hostname === AWS_TERRAIN_HOST) : null;
				await page.getByTestId('course-preview-open').click();
				const dialog = page.getByTestId('course-preview-3d');
				await expect(dialog.locator('[data-flyover-mode]')).toHaveAttribute(
					'data-flyover-mode',
					webgl2 ? 'static3d' : 'flat2d',
				);
				await terrain;
				await expect(dialog.getByTestId('course-preview-scrub')).toBeVisible();
				await expect(dialog.getByTestId('course-preview-export-video')).toHaveCount(0);
			} finally {
				await deleteRoute(routeId);
			}
		});
	});

	test.describe('as the route owner', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('the owner, who is served the unclipped line, is offered no export', async ({ page, mockRoute }) => {
			await page.emulateMedia({ reducedMotion: 'reduce' });
			await mockRoute(
				page,
				(url) => FALLBACK_TILE_ORIGINS.has(url.origin),
				(route) => route.fulfill({ status: 200, contentType: 'image/png', body: BLANK_TILE }),
			);
			const routeId = await insertPublicRoute(`Video owner ${Date.now()}`);
			try {
				await page.goto(`/routes/${routeId}`);
				const { webgl2 } = await exportCapable(page);
				await mockRoute(
					page,
					(url) => url.hostname === AWS_TERRAIN_HOST,
					(route) => route.fulfill({ status: 404 }),
					webgl2 ? {} : { neverFires: 'without WebGL2 the preview is flat and loads no terrain' },
				);
				const terrain = webgl2 ? page.waitForRequest((r) => new URL(r.url()).hostname === AWS_TERRAIN_HOST) : null;
				await page.getByTestId('course-preview-open').click();
				const dialog = page.getByTestId('course-preview-3d');
				await expect(dialog.getByTestId('course-preview-strip')).toBeVisible();
				await terrain;
				await expect(dialog.getByTestId('course-preview-scrub')).toBeVisible();
				await expect(dialog.getByTestId('course-preview-export-video')).toHaveCount(0);
			} finally {
				await deleteRoute(routeId);
			}
		});
	});
});
