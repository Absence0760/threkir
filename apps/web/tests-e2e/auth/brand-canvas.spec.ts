import { expect, test } from '@playwright/test';

/**
 * /login — the brand canvas either side of the 56rem breakpoint.
 *
 * The canvas is two mirror-image halves: a full-height `.brand-pane`
 * from 56rem up, and a short `.brand-band` below it. Each is
 * `display: none` where the other shows, and NEITHER is aria-hidden,
 * because each carries the page's only link home — hiding a focusable
 * subtree leaves the link focusable but nameless (axe aria-hidden-focus,
 * WCAG 4.1.2 + 2.4.3). So "exactly one logo link, at every width" is the
 * invariant, and a third copy inside the form card is what this file
 * exists to prevent coming back.
 */

const MOBILE = { width: 390, height: 844 };
const DESKTOP = { width: 1440, height: 900 };

test.describe('/login brand canvas', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('exactly one link home, on either side of the breakpoint', async ({ page }) => {
		await page.goto('/login');

		for (const viewport of [DESKTOP, MOBILE]) {
			await page.setViewportSize(viewport);
			const home = page.locator('a[href="/"]:visible');
			await expect(
				home,
				`${viewport.width}px: one visible link home, not ${await home.count()}`
			).toHaveCount(1);
			// Visible AND named: the accessible name is what the aria-hidden
			// defect took away while leaving the link in the tab order.
			await expect(home).toContainText('Threkir');
		}
	});

	test('the wide pane carries the product, the narrow band carries the header', async ({
		page
	}) => {
		await page.setViewportSize(DESKTOP);
		await page.goto('/login');

		const pane = page.locator('.brand-pane');
		await expect(pane).toBeVisible();
		await expect(page.locator('.brand-band')).toBeHidden();

		// The showcase is the product's own renderer over static demo
		// geometry — an <svg> drawn by TrackPreview, not an <img> of one.
		// A committed screenshot here would satisfy a smoke test and be
		// exactly the thing this surface is built not to ship.
		const showcase = pane.locator('figure.showcase');
		await expect(showcase).toBeVisible();
		await expect(showcase.locator('svg').first()).toBeVisible();
		await expect(showcase.locator('img')).toHaveCount(0);

		// The three figures, which are derived from the demo splits rather
		// than typed — demo_preview.test.ts owns the arithmetic; this
		// asserts they reach the pane at all.
		await expect(showcase.locator('.stat')).toHaveCount(3);
		await expect(showcase).toContainText('8.00');
		await expect(showcase).toContainText('39:14');
		await expect(showcase).toContainText('4:54');
	});

	test('the narrow band replaces the pane rather than joining it', async ({ page }) => {
		await page.setViewportSize(MOBILE);
		await page.goto('/login');

		await expect(page.locator('.brand-band')).toBeVisible();
		await expect(page.locator('.brand-pane')).toBeHidden();

		// The card rises INTO the band: its top edge sits above the band's
		// bottom edge, which is the whole point of the negative margin and
		// the one thing a later padding change would quietly undo.
		const band = await page.locator('.brand-band').boundingBox();
		const card = await page.locator('.login-card').boundingBox();
		expect(band, 'band must have a box').not.toBeNull();
		expect(card, 'card must have a box').not.toBeNull();
		expect(card!.y).toBeLessThan(band!.y + band!.height);
	});

	test('the eyebrow reads once per screen, not once per pane', async ({ page }) => {
		// Both halves of the canvas used to repeat the form card's own
		// kicker — "Welcome back" twice, 700px apart, at desktop width.
		await page.setViewportSize(DESKTOP);
		await page.goto('/login');

		await expect(page.getByText('Welcome back', { exact: true })).toHaveCount(1);
		await expect(page.locator('.brand-eyebrow:visible')).toHaveCount(1);
	});
});
