import type { Download, Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';

import { expect, test } from '../fixtures/test';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';
import type { TrackPoint } from '../../src/lib/types';

/**
 * The run share-image editor (issue #1273 item 2): the map card, the runner's
 * own photo, or a transparent sticker, in the layouts / inks / aspects / stats
 * the phone's share sheet offers. Pins what leaves the page: a 1080 px PNG,
 * a sticker cropped to its content with a transparent ground, a photo drawn
 * fresh so the original's EXIF never rides along, and a look remembered by
 * this browser.
 */

const TRACK: TrackPoint[] = Array.from({ length: 8 }, (_, i) => ({
	lat: -37.8 + i * 0.001,
	lng: 144.96 + (i % 2) * 0.0008,
	ele: 20 + i * 4,
	ts: new Date(Date.UTC(2026, 4, 10, 8, i)).toISOString(),
}));

const EXIF_MARKER = 'THREKIR_EXIF_GPS_MARKER';

interface Png {
	bytes: Buffer;
	width: number;
	height: number;
}

async function readPng(download: Download): Promise<Png> {
	const path = await download.path();
	const bytes = await readFile(path);
	expect(bytes.subarray(0, 8).toString('hex')).toBe('89504e470d0a1a0a');
	return { bytes, width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
}

/// The alpha of the PNG's top-left pixel, decoded by the browser.
async function cornerAlpha(page: Page, png: Png): Promise<number> {
	return page.evaluate(async (b64) => {
		const blob = await (await fetch(`data:image/png;base64,${b64}`)).blob();
		const bmp = await createImageBitmap(blob);
		const c = document.createElement('canvas');
		c.width = bmp.width;
		c.height = bmp.height;
		const ctx = c.getContext('2d')!;
		ctx.drawImage(bmp, 0, 0);
		return ctx.getImageData(0, 0, 1, 1).data[3];
	}, png.bytes.toString('base64'));
}

/// A JPEG made by the browser, with an APP1 Exif segment spliced in after the
/// SOI marker carrying a recognisable string, the shape a phone photo's GPS
/// block has on disk.
async function jpegWithExif(page: Page): Promise<Buffer> {
	const b64 = await page.evaluate(() => {
		const c = document.createElement('canvas');
		c.width = 640;
		c.height = 480;
		const ctx = c.getContext('2d')!;
		ctx.fillStyle = 'rgb(40, 90, 160)';
		ctx.fillRect(0, 0, 640, 480);
		ctx.fillStyle = 'rgb(230, 200, 60)';
		ctx.fillRect(200, 120, 240, 240);
		return c.toDataURL('image/jpeg', 0.9).split(',')[1];
	});
	const jpeg = Buffer.from(b64, 'base64');
	const body = Buffer.concat([
		Buffer.from('Exif\0\0', 'binary'),
		Buffer.from('MM\0*\0\0\0\x08', 'binary'),
		Buffer.from(EXIF_MARKER, 'ascii'),
	]);
	const len = Buffer.alloc(2);
	len.writeUInt16BE(body.length + 2);
	return Buffer.concat([jpeg.subarray(0, 2), Buffer.from([0xff, 0xe1]), len, body, jpeg.subarray(2)]);
}

async function openEditor(page: Page, runId: string) {
	await page.goto(`/runs/${runId}`);
	await page.locator('button[title="Share as image"]').click();
	const dialog = page.getByTestId('run-share-image-dialog');
	await expect(dialog).toBeVisible({ timeout: 15_000 });
	return dialog;
}

async function download(page: Page) {
	const pending = page.waitForEvent('download');
	await page.getByTestId('share-image-download').click();
	return pending;
}

test.describe('run share-image editor', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string;
	test.beforeEach(async () => {
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: '2026-05-10T08:00:00Z',
			distance_m: 5_000,
			duration_s: 1_500,
			metadata: { title: 'Share editor run', avg_bpm: 151 },
			track: TRACK,
		});
	});
	test.afterEach(async () => {
		await deleteRun(runId);
	});

	test('the map card exports a 1080 px PNG', async ({ page }) => {
		const dialog = await openEditor(page, runId);
		await expect(dialog.getByTestId('share-style-card')).toHaveAttribute('aria-checked', 'true');
		await expect(dialog.getByTestId('share-image-preview')).toBeVisible({ timeout: 15_000 });
		const png = await readPng(await download(page));
		expect(png.width).toBe(1080);
		expect(png.height).toBe(1080);
	});

	test('a sticker is a transparent PNG cropped to its content, and the look is remembered', async ({
		page,
	}) => {
		const dialog = await openEditor(page, runId);
		await dialog.getByTestId('share-style-sticker').click();
		await dialog.getByTestId('share-layout-strip').click();
		await dialog.getByTestId('share-ink-dark').click();
		// Only what the run measured is offered; heart rate was.
		await expect(dialog.getByTestId('share-stat-heartRate')).toBeVisible();
		await dialog.getByTestId('share-stat-heartRate').click();
		await expect(dialog.getByTestId('share-stat-heartRate')).toHaveAttribute('aria-pressed', 'true');
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });

		const png = await readPng(await download(page));
		expect(png.width).toBe(1080);
		// The strip is one wide line: cropped to it, the sticker is far
		// shorter than it is wide, where a fixed 4:5 canvas would be taller.
		expect(png.height).toBeLessThan(png.width / 2);
		expect(await cornerAlpha(page, png)).toBe(0);

		await page.reload();
		const again = await openEditor(page, runId);
		await again.getByTestId('share-style-sticker').click();
		await expect(again.getByTestId('share-layout-strip')).toHaveAttribute('aria-checked', 'true');
		await expect(again.getByTestId('share-ink-dark')).toHaveAttribute('aria-checked', 'true');
		await expect(again.getByTestId('share-stat-heartRate')).toHaveAttribute('aria-pressed', 'true');
	});

	test('a photo exports at the chosen aspect and carries none of the original EXIF', async ({
		page,
	}) => {
		const dialog = await openEditor(page, runId);
		const jpeg = await jpegWithExif(page);
		expect(jpeg.includes(Buffer.from(EXIF_MARKER))).toBe(true);

		await dialog.getByTestId('share-photo-input').setInputFiles({
			name: 'holiday.jpg',
			mimeType: 'image/jpeg',
			buffer: jpeg,
		});
		await dialog.getByTestId('share-style-photo').click();
		await dialog.getByTestId('share-aspect-story').click();
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
		const story = await readPng(await download(page));
		expect([story.width, story.height]).toEqual([1080, 1920]);
		expect(story.bytes.includes(Buffer.from(EXIF_MARKER))).toBe(false);
		expect(story.bytes.includes(Buffer.from('Exif'))).toBe(false);

		await dialog.getByTestId('share-aspect-post').click();
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
		const post = await readPng(await download(page));
		expect([post.width, post.height]).toEqual([1080, 1350]);
	});
});
