import { expect, test } from '../fixtures/test';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { pngPixels } from '../fixtures/png-pixels';
import { USER_A } from '../fixtures/users';
import type { TrackPoint } from '../../src/lib/types';

/**
 * The share editor's map card is a capture of the run page's off-screen
 * `.share-card` by html-to-image, which copies the node's computed style onto
 * its clone. The card used to carry its own `top/left: -9999px`, so the clone
 * was drawn outside the PNG: a fully transparent 1080 px image, shown as an
 * empty box with Download live, and passing a size-only check. The card is
 * now offset by a host around it, and a capture that is not opaque is refused
 * so the editor says so instead of offering a blank file.
 */

const TRACK: TrackPoint[] = Array.from({ length: 8 }, (_, i) => ({
	lat: -37.8 + i * 0.001,
	lng: 144.96 + (i % 2) * 0.0008,
	ele: 20 + i * 4,
	ts: new Date(Date.UTC(2026, 4, 10, 8, i)).toISOString(),
}));

test.describe('run share map card capture', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string;
	test.beforeEach(async () => {
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: '2026-05-10T08:00:00Z',
			distance_m: 5_000,
			duration_s: 1_500,
			metadata: { title: 'Share card capture run' },
			track: TRACK,
		});
	});
	test.afterEach(async () => {
		await deleteRun(runId);
	});

	test('the map card exports an opaque PNG of the card, not a blank one', async ({ page }) => {
		await page.goto(`/runs/${runId}`);
		await page.locator('button[title="Share image"]').click();
		const dialog = page.getByTestId('run-share-image-dialog');
		await expect(dialog.getByTestId('share-image-preview')).toBeVisible({ timeout: 15_000 });
		await expect(dialog.getByTestId('share-image-error')).toHaveCount(0);

		const pending = page.waitForEvent('download');
		await dialog.getByTestId('share-image-download').click();
		const png = await pngPixels(page, await pending);
		expect(png.width).toBe(1080);
		expect(png.height).toBe(1080);
		expect(png.opaque).toBeGreaterThanOrEqual(0.99);
		// The gradient's first stop, #C24E24, sits under the top-left corner.
		const [r, , b, a] = png.corner;
		expect(a).toBe(255);
		expect(r).toBeGreaterThan(b);
	});

	test('Grisnir signs the bottom-right corner under the stats and leaves with the mark', async ({ page }) => {
		await page.goto(`/runs/${runId}`);
		await page.locator('button[title="Share image"]').click();
		const dialog = page.getByTestId('run-share-image-dialog');
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });

		const grisnir = page.getByTestId('share-card-grisnir');
		await expect(grisnir).toBeAttached();
		const rects = await page.evaluate(() => {
			const r = (sel: string) => document.querySelector(sel)!.getBoundingClientRect().toJSON() as DOMRect;
			const img = document.querySelector<HTMLImageElement>('[data-testid="share-card-grisnir"]')!;
			return { card: r('[data-testid="share-card"]'), stats: r('.share-card-stats'), goat: r('[data-testid="share-card-grisnir"]'), loaded: img.naturalWidth };
		});
		expect(rects.loaded).toBeGreaterThan(0);
		expect(rects.goat.top).toBeGreaterThanOrEqual(rects.stats.bottom);
		expect(rects.goat.bottom).toBeLessThanOrEqual(rects.card.bottom);
		expect(rects.goat.right).toBeLessThanOrEqual(rects.card.right);
		expect(rects.goat.left).toBeGreaterThan(rects.card.left + rects.card.width / 2);

		await dialog.getByTestId('share-mark').uncheck();
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
		await expect(grisnir).toHaveCount(0);
	});

	test('a card drawn outside its frame shows an error with a retry, and Download stays off', async ({ page }) => {
		await page.goto(`/runs/${runId}`);
		await expect(page.getByTestId('share-card')).toBeAttached();
		// Put the old offset back on the captured node itself.
		const offset = await page.addStyleTag({
			content: '[data-testid="share-card"] { position: fixed !important; top: -9999px !important; left: -9999px !important; }',
		});
		await page.locator('button[title="Share image"]').click();
		const dialog = page.getByTestId('run-share-image-dialog');

		const error = dialog.getByTestId('share-image-error');
		await expect(error).toBeVisible({ timeout: 15_000 });
		await expect(error).toHaveAttribute('role', 'alert');
		await expect(dialog.getByTestId('share-image-preview')).toHaveCount(0);
		await expect(dialog.getByTestId('share-image-download')).toBeDisabled();

		await offset.evaluate((el) => el.parentNode?.removeChild(el));
		await dialog.getByTestId('share-image-retry').click();
		await expect(dialog.getByTestId('share-image-preview')).toBeVisible({ timeout: 15_000 });
		await expect(error).toHaveCount(0);
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled();
	});
});
