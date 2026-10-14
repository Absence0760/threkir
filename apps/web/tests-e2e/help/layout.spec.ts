import { expect, test, type Page } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * The help pages sit in the same page frame as every other signed-in page.
 *
 * Each help wrapper used to carry its own max-width (64rem on the contents,
 * 48rem on a guide and on search) ON the padded wrapper, so on a wide window
 * the frame stopped short of the main column and left a dead band beside the
 * cards — roughly 460px of it at 1870px. The frame contract the other pages
 * follow is: the wrapper fills <main>, inset by --page-padding-x on both
 * sides. Long-form text still caps its measure, but inside the frame.
 *
 * Asserted as geometry against /history rather than as CSS, so whichever
 * rule reintroduces a capped frame is caught.
 */

const DESKTOP = { width: 1870, height: 1000 };
const PHONE = { width: 390, height: 844 };

type Frame = { mainRight: number; frameRight: number; padLeft: number; padRight: number };

const frameOf = async (page: Page, selector: string): Promise<Frame> => {
	const el = page.locator(selector).first();
	await expect(el).toBeVisible({ timeout: 10_000 });
	return el.evaluate((node) => {
		const main = document.getElementById('main-content');
		if (!main) throw new Error('no #main-content');
		const style = getComputedStyle(node);
		return {
			mainRight: Math.round(main.getBoundingClientRect().right),
			frameRight: Math.round(node.getBoundingClientRect().right),
			padLeft: Math.round(parseFloat(style.paddingLeft)),
			padRight: Math.round(parseFloat(style.paddingRight)),
		};
	});
};

const HELP_PAGES = [
	{ path: '/help', frame: '.help-page' },
	{ path: '/help/using-help', frame: '.help-guide-page' },
	{ path: '/help/search?q=help', frame: '.help-search-page' },
];

test.describe('/help — shared page frame', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('every help page fills the main column like /history does', async ({ page }) => {
		await page.setViewportSize(DESKTOP);
		await page.goto('/history');
		const reference = await frameOf(page, '.page');
		expect(reference.frameRight, '/history fills the main column').toBe(reference.mainRight);

		for (const { path, frame } of HELP_PAGES) {
			await page.goto(path);
			const got = await frameOf(page, frame);
			expect(got.frameRight, `${path} must reach the main column's edge`).toBe(got.mainRight);
			expect(got.padLeft, `${path} left gutter`).toBe(reference.padLeft);
			expect(got.padRight, `${path} right gutter`).toBe(reference.padRight);
		}
	});

	test('the guide text keeps a reading measure inside the full frame', async ({ page }) => {
		await page.setViewportSize(DESKTOP);
		await page.goto('/help/using-help');
		const guide = page.getByTestId('help-guide');
		await expect(guide).toBeVisible({ timeout: 10_000 });
		const box = await guide.boundingBox();
		const frame = await frameOf(page, '.help-guide-page');
		expect(box).not.toBeNull();
		// The article stops well short of the frame's inner edge at this width.
		expect(box!.x + box!.width).toBeLessThan(frame.frameRight - frame.padRight - 100);
	});

	test('no help page scrolls sideways on a phone', async ({ page }) => {
		await page.setViewportSize(PHONE);
		for (const { path, frame } of HELP_PAGES) {
			await page.goto(path);
			await expect(page.locator(frame).first()).toBeVisible({ timeout: 10_000 });
			const overflow = await page.evaluate(
				() => document.documentElement.scrollWidth - document.documentElement.clientWidth
			);
			expect(overflow, `${path} overflows the phone viewport`).toBeLessThanOrEqual(0);
		}
	});
});
