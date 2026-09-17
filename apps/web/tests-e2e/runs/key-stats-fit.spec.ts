import { expect, test, type Page } from '@playwright/test';

import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] key-stat tiles state their figures whole (issue #902).
 *
 * The value cell was `nowrap` + `overflow: hidden` + `text-overflow: ellipsis`
 * inside a two-column panel, so `12.0 km/h` rendered as `12.0 k…` and a pace as
 * `5:00 /…` — a figure with its unit cut off. A value now wraps between number
 * and unit instead. The measurement is `scrollWidth` against `clientWidth` on
 * every value, the same one the icon-ligature and builder-panel-fit specs use:
 * clipped text is invisible to a text assertion, which still reads the full
 * string out of the DOM.
 *
 * The same tiles used to state pace AND speed for every activity. Speed is now
 * the tile for a ride and pace for everything else, as on mobile.
 */

async function clippedValues(page: Page): Promise<string[]> {
	return page
		.locator('.key-stats .key-stat-value')
		.evaluateAll((els) =>
			els
				.filter((el) => el.scrollWidth > el.clientWidth + 1)
				.map((el) => el.textContent?.trim() ?? '')
		);
}

const labels = (page: Page) => page.locator('.key-stats .key-stat-label');

test.describe('/runs/[id] key stats', () => {
	test.use({ storageState: USER_A.storageStatePath, viewport: { width: 1280, height: 720 } });

	test('a run states pace, not speed, and no value is clipped', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 9_000,
			duration_s: 2_700,
			activity_type: 'run'
		});
		try {
			await page.goto(`/runs/${runId}`);
			await expect(labels(page).filter({ hasText: 'Avg Pace' })).toHaveCount(1);
			await expect(labels(page).filter({ hasText: 'Avg Speed' })).toHaveCount(0);
			expect(await clippedValues(page)).toEqual([]);
		} finally {
			await deleteRun(runId);
		}
	});

	test('a ride states speed, not pace, and the speed is not clipped', async ({ page }) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 30_000,
			duration_s: 3_600,
			activity_type: 'cycle'
		});
		try {
			await page.goto(`/runs/${runId}`);
			const speed = page.locator('.key-stat', {
				has: page.locator('.key-stat-label', { hasText: 'Avg Speed' })
			});
			await expect(speed.locator('.key-stat-value')).toHaveText('30.0 km/h');
			await expect(labels(page).filter({ hasText: 'Avg Pace' })).toHaveCount(0);
			expect(await clippedValues(page)).toEqual([]);
		} finally {
			await deleteRun(runId);
		}
	});
});
