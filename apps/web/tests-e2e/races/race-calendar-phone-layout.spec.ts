import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { deleteRaceListing, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * The race calendar at phone width (race_calendar.md § Filters). The search
 * field stayed on the page and every other filter moved behind one Filters
 * control, because the stacked filter block used to push the first race below
 * the fold. The list is the point of the page, so the races have to start on
 * the first screen, and the filter state has to stay legible with the panel
 * closed: a count on the control and one removable chip per filter.
 */

test.describe('/races — phone layout', () => {
	test.use({ storageState: USER_A.storageStatePath, viewport: { width: 390, height: 844 } });

	const listings: string[] = [];

	test.afterEach(async () => {
		for (const id of listings.splice(0)) {
			try {
				await deleteRaceListing(id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('races start in the first viewport, nothing scrolls sideways, and a filter reads as a chip', async ({
		page
	}) => {
		const stamp = Date.now();
		for (let i = 0; i < 3; i++) {
			listings.push(
				await insertRaceListing({
					provider: 'manual',
					name: `E2E Phone Layout Half Marathon With A Long Name ${stamp} ${i}`,
					race_date: browserDate(60 + i),
					distance_m: 21097,
					location_label: 'Richmond, VA',
					entry_url: 'https://example.com/register',
					is_verified: true
				})
			);
		}

		await page.goto('/races');
		await page.getByTestId('races-search').fill(String(stamp));
		const cards = page.getByTestId('race-card').filter({ hasText: String(stamp) });
		await expect(cards).toHaveCount(3, { timeout: 15_000 });

		const viewportHeight = page.viewportSize()!.height;
		const first = await cards.nth(0).boundingBox();
		const second = await cards.nth(1).boundingBox();
		expect(first!.y, 'the first race starts on the first screen').toBeLessThan(viewportHeight);
		expect(second!.y, 'a second race starts on the first screen too').toBeLessThan(viewportHeight);

		const fits = await page.evaluate(
			() => document.documentElement.scrollWidth <= document.documentElement.clientWidth
		);
		expect(fits, 'no horizontal scroll at 390 px').toBe(true);

		// Closed by default, and no count while nothing is on.
		const toggle = page.getByTestId('races-filters-toggle');
		await expect(toggle).toHaveAttribute('aria-expanded', 'false');
		await expect(page.getByTestId('races-filters-panel')).toBeHidden();
		await expect(page.getByTestId('races-filter-count')).toHaveCount(0);

		await toggle.click();
		await expect(toggle).toHaveAttribute('aria-expanded', 'true');
		await page.getByTestId('races-dist-half').click();
		await expect(page.getByTestId('races-dist-half')).toHaveAttribute('aria-pressed', 'true');

		await expect(page.getByTestId('races-filter-count')).toHaveText('1');
		const chip = page.getByTestId('races-chip-distance');
		await expect(chip).toBeVisible();
		await expect(chip).toHaveAttribute('aria-label', /Half/);
		await expect(cards).toHaveCount(3, { timeout: 15_000 });

		// Closing the panel keeps the state on screen.
		await toggle.click();
		await expect(page.getByTestId('races-filters-panel')).toBeHidden();
		await expect(chip).toBeVisible();

		await chip.click();
		await expect(page.getByTestId('races-filter-count')).toHaveCount(0);
		await expect(page.getByTestId('races-active-filters')).toHaveCount(0);
	});
});
