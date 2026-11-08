import type { Download, Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';

import { expect, test } from '../fixtures/test';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';
import type { TrackPoint } from '../../src/lib/types';

/**
 * The run share-image editor (issue #1273 item 2): the map card, the runner's
 * own photo, or a transparent sticker, in the layouts / inks / aspects / stats
 * the phone's share sheet offers. Pins what leaves the page: a 1080 px PNG,
 * a sticker cropped to its content with a transparent ground, a photo drawn
 * fresh so the original's EXIF never rides along, a photo's stats exported
 * where the runner moved them, a look remembered by this browser, and the
 * occasion stickers (issue #1295) offered only for a run that has their data.
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

	test('an occasion sticker is offered only when the run has its data, and exports transparent', async ({ page }) => {
		const dialog = await openEditor(page, runId);
		await dialog.getByTestId('share-style-sticker').click();
		await expect(dialog.getByTestId('share-kind-stats')).toHaveAttribute('aria-checked', 'true');
		await expect(dialog.getByTestId('share-kind-route')).toBeVisible();
		// No record, no race link, no park course, no badge: none of those stickers is offered.
		for (const hidden of ['pr', 'race', 'course', 'badge']) {
			await expect(dialog.getByTestId(`share-kind-${hidden}`)).toHaveCount(0);
		}

		await dialog.getByTestId('share-kind-route').click();
		await expect(dialog.getByTestId('share-kind-route')).toHaveAttribute('aria-checked', 'true');
		// The layouts and stat chips belong to the stats sticker.
		await expect(dialog.getByTestId('share-layout-stack')).toHaveCount(0);
		await expect(dialog.getByTestId('share-stat-distance')).toHaveCount(0);
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
		const png = await readPng(await download(page));
		expect(png.width).toBe(1080);
		expect(await cornerAlpha(page, png)).toBe(0);
	});

	test('a race run offers the race sticker, and a run with no race falls back to stats', async ({ page }) => {
		const raceRunId = await insertRun({
			user_id: USER_A.id,
			started_at: '2026-05-03T07:00:00Z',
			distance_m: 5_000,
			duration_s: 1_480,
			metadata: { title: 'Race day', race_name: 'Riverside 5K', chip_time: '24:31' },
			track: TRACK,
		});
		try {
			const dialog = await openEditor(page, raceRunId);
			await dialog.getByTestId('share-style-sticker').click();
			await dialog.getByTestId('share-kind-race').click();
			await expect(dialog.getByTestId('share-kind-race')).toHaveAttribute('aria-checked', 'true');
			await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
			const png = await readPng(await download(page));
			expect(png.width).toBe(1080);
			expect(await cornerAlpha(page, png)).toBe(0);

			// The remembered race kind cannot print on a run with no race.
			const plain = await openEditor(page, runId);
			await plain.getByTestId('share-style-sticker').click();
			await expect(plain.getByTestId('share-kind-race')).toHaveCount(0);
			await expect(plain.getByTestId('share-kind-stats')).toHaveAttribute('aria-checked', 'true');
		} finally {
			await deleteRun(raceRunId);
		}
	});

	test('a run that completed a park course offers the course sticker', async ({ page }) => {
		const admin = getAdminClient();
		const tag = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		const { data: seg, error: segErr } = await admin
			.from('global_segments')
			.insert({
				name: `E2E Sticker Loop ${tag}`,
				waypoints: [TRACK[0], TRACK[TRACK.length - 1]].map((p) => ({ lat: p.lat, lng: p.lng })),
				distance_m: 1000,
				surface: 'trail',
				country_code: 'US',
			})
			.select('id')
			.single();
		if (segErr) throw segErr;
		const { data: park, error: parkErr } = await admin
			.from('parks')
			.insert({
				slug: `e2e-sticker-${tag}`,
				name: `E2E Sticker Park ${tag}`,
				agency: 'state',
				region_code: 'US-VA',
				country_code: 'US',
				timezone: 'America/New_York',
			})
			.select('id')
			.single();
		if (parkErr) throw parkErr;
		try {
			const { error: courseErr } = await admin.from('park_courses').insert({
				park_id: park.id,
				global_segment_id: seg.id,
				slug: 'loop',
				course_shape: 'loop',
				geometry_source: 'osm',
			});
			if (courseErr) throw courseErr;
			const { error: effortErr } = await admin.from('global_segment_efforts').insert({
				global_segment_id: seg.id,
				run_id: runId,
				user_id: USER_A.id,
				time_seconds: 1_400,
				started_at: '2026-05-10T08:00:00Z',
			});
			if (effortErr) throw effortErr;

			const dialog = await openEditor(page, runId);
			await dialog.getByTestId('share-style-sticker').click();
			await dialog.getByTestId('share-kind-course').click();
			await expect(dialog.getByTestId('share-kind-course')).toHaveAttribute('aria-checked', 'true');
			await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
			const png = await readPng(await download(page));
			expect(png.width).toBe(1080);
			expect(await cornerAlpha(page, png)).toBe(0);
		} finally {
			await admin.from('parks').delete().eq('id', park.id).then(() => {}, () => {});
			await admin.from('global_segments').delete().eq('id', seg.id).then(() => {}, () => {});
		}
	});

	test('the streak sticker counts the days up to this run', async ({ page }) => {
		const dayBefore = await insertRun({
			user_id: USER_A.id,
			started_at: '2026-05-09T08:00:00Z',
			distance_m: 3_000,
			duration_s: 1_000,
			track: TRACK,
		});
		try {
			const dialog = await openEditor(page, runId);
			await dialog.getByTestId('share-style-sticker').click();
			await dialog.getByTestId('share-kind-streak').click();
			await expect(dialog.getByTestId('share-kind-streak')).toHaveAttribute('aria-checked', 'true');
			await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
			expect(await cornerAlpha(page, await readPng(await download(page)))).toBe(0);
		} finally {
			await deleteRun(dayBefore);
		}
	});
});
