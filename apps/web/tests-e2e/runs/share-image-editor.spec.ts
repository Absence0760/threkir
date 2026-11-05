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
 * fresh so the original's EXIF never rides along, a photo's stats exported
 * where the runner moved them, and a look remembered by this browser.
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

/// The box the light ink's white pixels span in a PNG, in its own pixels: the
/// title, stats, route and mark, and nothing of the blue-and-yellow photo.
async function inkBox(page: Page, png: Png) {
	return page.evaluate(async (b64) => {
		const blob = await (await fetch(`data:image/png;base64,${b64}`)).blob();
		const bmp = await createImageBitmap(blob);
		const c = document.createElement('canvas');
		c.width = bmp.width;
		c.height = bmp.height;
		const ctx = c.getContext('2d')!;
		ctx.drawImage(bmp, 0, 0);
		const { data } = ctx.getImageData(0, 0, c.width, c.height);
		let [left, top, right, bottom] = [Infinity, Infinity, -Infinity, -Infinity];
		for (let y = 0; y < c.height; y++) {
			for (let x = 0; x < c.width; x++) {
				const i = (y * c.width + x) * 4;
				if (data[i] > 245 && data[i + 1] > 245 && data[i + 2] > 245) {
					left = Math.min(left, x);
					right = Math.max(right, x);
					top = Math.min(top, y);
					bottom = Math.max(bottom, y);
				}
			}
		}
		return { left, top, right, bottom };
	}, png.bytes.toString('base64'));
}

/// The block's handle as fractions of the preview it sits on.
async function blockFractions(dialog: ReturnType<Page['getByTestId']>) {
	const stage = (await dialog.getByTestId('share-image-preview').boundingBox())!;
	const block = (await dialog.getByTestId('share-placement-block').boundingBox())!;
	return {
		left: (block.x - stage.x) / stage.width,
		top: (block.y - stage.y) / stage.height,
		width: block.width / stage.width,
		height: block.height / stage.height,
	};
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

	test('turning the Threkir mark off drops the signature from the sticker, and stays off', async ({
		page,
	}) => {
		const dialog = await openEditor(page, runId);
		await dialog.getByTestId('share-style-sticker').click();
		const mark = dialog.getByTestId('share-mark');
		await expect(mark).toBeChecked();
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
		const signed = await readPng(await download(page));

		await mark.uncheck();
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
		const bare = await readPng(await download(page));
		// Cropped to its content, the sticker loses the signature's height.
		expect(bare.height).toBeLessThan(signed.height);

		await page.reload();
		const again = await openEditor(page, runId);
		await expect(again.getByTestId('share-mark')).not.toBeChecked();
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

	test('the photo stats move and resize by pointer, grip, keyboard and wheel, export where they sit, and are remembered per aspect', async ({
		page,
	}) => {
		const dialog = await openEditor(page, runId);
		const jpeg = await jpegWithExif(page);
		await dialog.getByTestId('share-photo-input').setInputFiles({ name: 'p.jpg', mimeType: 'image/jpeg', buffer: jpeg });
		await dialog.getByTestId('share-style-photo').click();
		await dialog.getByTestId('share-aspect-story').click();
		const block = dialog.getByTestId('share-placement-block');
		const reset = dialog.getByTestId('share-placement-reset');
		await expect(block).toBeVisible({ timeout: 15_000 });
		await expect(block).toHaveAccessibleName('Stats position');
		await expect(reset).toBeDisabled();
		const start = await blockFractions(dialog);
		// The default sits on the frame's bottom edge, clear of the reply bar.
		expect(start.top + start.height).toBeLessThanOrEqual(0.87 + 0.01);

		// Shrink with the keyboard, then move left and up with the arrows.
		await block.focus();
		await page.keyboard.press('-');
		await page.keyboard.press('-');
		await expect.poll(async () => (await blockFractions(dialog)).width).toBeLessThan(start.width * 0.9);
		for (let i = 0; i < 4; i++) await page.keyboard.press('Shift+ArrowLeft');
		const keyed = await blockFractions(dialog);
		expect(keyed.left).toBeLessThan((1 - keyed.width) / 2 - 0.05);

		// Drag it up with the pointer.
		const box = (await block.boundingBox())!;
		await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
		await page.mouse.down();
		await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2 - 120, { steps: 8 });
		await page.mouse.up();
		const dragged = await blockFractions(dialog);
		expect(dragged.top).toBeLessThan(keyed.top - 0.1);
		await expect(reset).toBeEnabled();

		// The wheel resizes too.
		const before = dragged.width;
		await block.hover();
		await page.mouse.wheel(0, 200);
		await expect.poll(async () => (await blockFractions(dialog)).width).toBeLessThan(before);

		// And so does the corner grip, about the block's centre.
		const wheeled = await blockFractions(dialog);
		const grip = (await dialog.getByTestId('share-placement-grip').boundingBox())!;
		const gx = grip.x + grip.width / 2;
		const gy = grip.y + grip.height / 2;
		const now = (await block.boundingBox())!;
		await page.mouse.move(gx, gy);
		await page.mouse.down();
		await page.mouse.move(
			gx - (gx - (now.x + now.width / 2)) * 0.2,
			gy - (gy - (now.y + now.height / 2)) * 0.2,
			{ steps: 6 },
		);
		await page.mouse.up();
		await expect.poll(async () => (await blockFractions(dialog)).width).toBeLessThan(wheeled.width * 0.95);
		const placed = await blockFractions(dialog);

		// What downloads is what the editor shows: the white ink sits inside the
		// block, at the same fractions of the 1080 x 1920 export.
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
		const png = await readPng(await download(page));
		expect([png.width, png.height]).toEqual([1080, 1920]);
		const ink = await inkBox(page, png);
		const slack = 6;
		expect(ink.left).toBeGreaterThanOrEqual(placed.left * 1080 - slack);
		expect(ink.right).toBeLessThanOrEqual((placed.left + placed.width) * 1080 + slack);
		expect(ink.top).toBeGreaterThanOrEqual(placed.top * 1920 - slack);
		expect(ink.bottom).toBeLessThanOrEqual((placed.top + placed.height) * 1920 + slack);

		// The post keeps a placement of its own.
		await dialog.getByTestId('share-aspect-post').click();
		await expect(reset).toBeDisabled();

		await page.reload();
		const again = await openEditor(page, runId);
		await again.getByTestId('share-photo-input').setInputFiles({ name: 'p.jpg', mimeType: 'image/jpeg', buffer: jpeg });
		await again.getByTestId('share-style-photo').click();
		await again.getByTestId('share-aspect-story').click();
		await expect(again.getByTestId('share-placement-block')).toBeVisible({ timeout: 15_000 });
		const restored = await blockFractions(again);
		for (const k of ['left', 'top', 'width', 'height'] as const) {
			expect(Math.abs(restored[k] - placed[k]), k).toBeLessThan(0.01);
		}

		await again.getByTestId('share-placement-reset').click();
		await expect(again.getByTestId('share-placement-reset')).toBeDisabled();
		const back = await blockFractions(again);
		for (const k of ['left', 'top', 'width', 'height'] as const) {
			expect(Math.abs(back[k] - start[k]), k).toBeLessThan(0.01);
		}
	});
});
