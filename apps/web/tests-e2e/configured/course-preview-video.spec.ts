import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { BLANK_TILE, FALLBACK_TILE_ORIGINS } from '../fixtures/map-tiles';
import { deleteRoute } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * The flyover video export in the 3D course preview (issue #1273 item 1,
 * decisions § 2259) where it is offered. This lane sets PUBLIC_TILE_STYLE_URL,
 * which stands for a developer's own tileserver: a keyless build offers no
 * export at all (routes/course-preview-video.spec.ts pins that). The override
 * names the OSM fallback style so every tile it asks for is the one the spec
 * stubs; nothing leaves the runner. Which mode a headless browser gets depends on its GPU,
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

test.describe('/routes/[id] flyover video export with a permitted basemap', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('under reduced motion the export is offered, starts rendering, and cancels back to the button', async ({
		page,
		mockRoute,
	}) => {
		// The render is real work on a GPU-less runner: SwiftShader rasterizes
		// the 1080x1920 map when each frame is copied out, measured at ~13 s
		// for the first frame (shaders, terrain) and ~0.8 s a frame after on
		// four cores, so reaching 1% (four frames) needs the progress wait's
		// 60 s on top of the page and preview setup.
		test.setTimeout(90_000);
		await page.emulateMedia({ reducedMotion: 'reduce' });
		await mockRoute(
			page,
			(url) => FALLBACK_TILE_ORIGINS.has(url.origin),
			(route) => route.fulfill({ status: 200, contentType: 'image/png', body: BLANK_TILE }),
		);
		const routeId = await insertPublicRoute(`Video export ${Date.now()}`);
		try {
			await page.goto(`/routes/${routeId}`);
			const { webgl2, encoder } = await exportCapable(page);
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
			const exportButton = dialog.getByTestId('course-preview-export-video');
			if (!webgl2 || !encoder) {
				await expect(exportButton).toHaveCount(0);
				return;
			}
			await exportButton.click();
			// A whole render takes minutes on a software GPU, so the case pins
			// that frames are being made and that Cancel stops it; the encoder
			// and muxer are pinned by their unit suites.
			const progress = dialog.getByTestId('course-preview-video-progress');
			await expect(progress).toContainText(/Making your video… [1-9]\d*%/, { timeout: 60_000 });
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			await expect(progress).toHaveCount(0);
			await expect(exportButton).toBeVisible();
		} finally {
			await deleteRoute(routeId);
		}
	});
});
