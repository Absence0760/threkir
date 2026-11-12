import { readFile } from 'node:fs/promises';

import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { browserYear } from '../fixtures/dates';
import { acceptCookieConsent } from '../fixtures/helpers';
import { FALLBACK_TILE_ORIGINS } from '../fixtures/map-tiles';
import { USER_A } from '../fixtures/users';

/**
 * The recap slideshow video (issue #1273 item 8, decisions § 2269). Whether a
 * headless browser can encode depends on its build, so each case asks the
 * browser and asserts what that answer implies rather than skipping.
 */

const YEAR = browserYear();

/// The slides are type and bars only: no map, so no tile or terrain host is
/// ever asked for anything while one is made.
const drawsAMap = (url: URL) =>
	FALLBACK_TILE_ORIGINS.has(url.origin) ||
	url.hostname === 'maptiler.com' ||
	url.hostname.endsWith('.maptiler.com') ||
	url.hostname === 'elevation-tiles-prod.s3.amazonaws.com';

async function canEncode(page: Page): Promise<boolean> {
	return page.evaluate(async () => {
		if (typeof VideoEncoder !== 'undefined') {
			for (const codec of ['avc1.640028', 'avc1.4d0028', 'avc1.42e028']) {
				try {
					const r = await VideoEncoder.isConfigSupported({ codec, width: 1080, height: 1920, bitrate: 8e6, framerate: 30 });
					if (r.supported) return true;
				} catch {
					// unknown codec string
				}
			}
		}
		return (
			typeof MediaRecorder !== 'undefined' &&
			typeof HTMLCanvasElement.prototype.captureStream === 'function' &&
			['video/mp4', 'video/webm'].some((t) => MediaRecorder.isTypeSupported(t))
		);
	});
}

async function openRecap(page: Page, query = '') {
	await page.goto(`/recap/${YEAR}${query}`);
	await expect(page.getByText(`My ${YEAR} in running`).first()).toBeVisible({ timeout: 15_000 });
}

test.describe('/recap/[year] slideshow video', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
	});

	test('makes a 1080x1920 file and hands it over as a download', async ({ page, mockRoute }) => {
		test.setTimeout(240_000);
		await mockRoute(page, drawsAMap, (route) => route.abort(), {
			neverFires: 'the recap slideshow draws no map, so it reaches no tile or terrain host',
		});
		await openRecap(page);
		const make = page.getByTestId('recap-make-video');

		if (!(await canEncode(page))) {
			await expect(page.getByTestId('recap-video-unsupported')).toBeVisible();
			await expect(make).toHaveCount(0);
			return;
		}

		await make.click();
		await expect(page.getByTestId('recap-video-progress')).toBeVisible();
		const preview = page.getByTestId('recap-video-preview');
		await expect(preview).toBeVisible({ timeout: 200_000 });

		const size = await preview.evaluate(
			(v: HTMLVideoElement) =>
				new Promise<{ w: number; h: number }>((resolve, reject) => {
					const done = () => resolve({ w: v.videoWidth, h: v.videoHeight });
					if (v.readyState >= 1) return done();
					v.addEventListener('loadedmetadata', done, { once: true });
					v.addEventListener('error', () => reject(new Error(`video error ${v.error?.code}`)), { once: true });
				}),
		);
		expect(size).toEqual({ w: 1080, h: 1920 });

		// Desktop Chromium has no file share sheet, so the file is downloaded.
		const download = page.waitForEvent('download');
		await page.getByTestId('recap-save-video').click();
		const file = await download;
		expect(file.suggestedFilename()).toMatch(new RegExp(`^threkir-recap-${YEAR}\\.(mp4|webm)$`));
		const bytes = await readFile((await file.path())!);
		expect(bytes.length).toBeGreaterThan(10_000);
		if (file.suggestedFilename().endsWith('.mp4')) {
			expect(bytes.subarray(4, 8).toString('latin1')).toBe('ftyp');
		}
		await expect(page.getByText('Video downloaded.')).toBeVisible();
	});

	test('?video=1 from the phone starts the video without a tap, and Cancel stops it', async ({ page }) => {
		await openRecap(page, '?video=1');
		if (!(await canEncode(page))) {
			await expect(page.getByTestId('recap-video-unsupported')).toBeVisible();
			return;
		}
		await expect(page.getByTestId('recap-video-progress')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('recap-make-video')).toHaveCount(0);
		await page.getByRole('button', { name: 'Cancel' }).click();
		await expect(page.getByTestId('recap-video-progress')).toHaveCount(0);
		await expect(page.getByTestId('recap-make-video')).toBeVisible();
	});

	test('a browser that cannot encode gets a note, not a dead button', async ({ page }) => {
		await page.addInitScript(() => {
			for (const name of ['VideoEncoder', 'VideoFrame', 'MediaRecorder']) {
				Object.defineProperty(window, name, { value: undefined, configurable: true });
			}
		});
		await openRecap(page);
		await expect(page.getByTestId('recap-video-unsupported')).toHaveText(
			"This browser can't make videos. A recent Chrome, Edge or Safari can.",
		);
		await expect(page.getByTestId('recap-make-video')).toHaveCount(0);
		await expect(page.getByTestId('recap-share-story')).toBeVisible();
	});
});
