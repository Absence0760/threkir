import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /dashboard — the shape of the page, and the honesty of the mileage axis.
 *
 * Every card used to be a full-width slab in one flex column, so a desktop
 * screen showed a single column of twenty of them. The cards of equal weight
 * now flow in auto-fit bands. What is worth pinning is not the pixel layout
 * but the two properties a later CSS edit could quietly undo: that a wide
 * viewport puts band-mates on ONE row, and that a phone puts them on
 * separate ones.
 */

const MOBILE = { width: 390, height: 844 };
const DESKTOP = { width: 1440, height: 900 };

test.describe('/dashboard layout', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('band-mates share a row on desktop and stack on a phone', async ({ page }) => {
		await page.setViewportSize(DESKTOP);
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		const band = page.locator('.metric-band').first();
		await expect(band).toBeVisible();

		// Two cards in the same band, both rendered: their top edges must
		// agree, which is the whole claim of the band.
		const cards = band.locator(':scope > section');
		const count = await cards.count();
		test.skip(count < 2, 'this account renders fewer than two cards in the first band');

		const first = await cards.nth(0).boundingBox();
		const second = await cards.nth(1).boundingBox();
		expect(first).not.toBeNull();
		expect(second).not.toBeNull();
		expect(
			Math.abs(first!.y - second!.y),
			'band-mates must sit on one row at 1440px'
		).toBeLessThan(4);
		expect(second!.x, 'and side by side, not stacked').toBeGreaterThan(first!.x);

		// A phone has no room for two columns of cards; the band's minmax
		// floor has to give way rather than squeeze both into 190px.
		await page.setViewportSize(MOBILE);
		await page.waitForTimeout(300);
		const firstNarrow = await cards.nth(0).boundingBox();
		const secondNarrow = await cards.nth(1).boundingBox();
		expect(
			secondNarrow!.y,
			'on a phone the second card must drop below the first'
		).toBeGreaterThan(firstNarrow!.y);
	});

	test('the mileage window is all twelve weeks or none', async ({ page }) => {
		await page.setViewportSize(DESKTOP);
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		const bars = page.locator('.bar-col');
		const drawn = await bars.count();

		// The property, stated as the code states it: a partial window is the
		// defect. Either nothing in the last twelve weeks — in which case the
		// card shows its own copy rather than twelve empty slots — or all
		// twelve buckets, including the weeks with no run in them. Which of
		// the two depends on how old the seeded runs are on the day the suite
		// runs, and that is exactly why this asserts the invariant instead of
		// a count.
		if (drawn === 0) {
			await expect(page.locator('.chart')).toHaveCount(0);
			return;
		}
		expect(drawn, 'a continuous window is twelve buckets, not just the busy ones').toBe(12);

		// At least one real bar, or the empty branch above should have run.
		const empties = await page.locator('.bar-col.empty').count();
		expect(empties).toBeLessThan(12);

		// The axis label is formatted in its own right, not cut out of the
		// full date: `split(' ')[0]` gave "Aug" for every week of August in
		// en-US, and the untranslated whole date in ja. In the suite's locale
		// a weekly label is a day of the month.
		for (const label of await page.locator('.bar-label').allInnerTexts()) {
			expect(label.trim(), 'a weekly axis label must be a day number').toMatch(/^\d{1,2}$/);
		}
	});
});
