import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { deleteRaceListing, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * The race calendar's Recent results view (race_calendar.md, decisions § 2083).
 *
 * Upcoming lists races from today on, so a race the runner has already run is
 * not on it. Recent results asks the server for the last 30 days newest first;
 * the past race appears there, ahead of an older one, with its import offered.
 */

test.describe('/races — Recent results', () => {
	test.use({ storageState: USER_A.storageStatePath });

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

	test('a race run last week is under Recent results, newest first, with its import', async ({
		page
	}) => {
		const stamp = Date.now();
		const newer = `E2E Recent Newer ${stamp}`;
		const older = `E2E Recent Older ${stamp}`;
		listings.push(
			await insertRaceListing({ provider: 'manual', name: older, race_date: browserDate(-20) }),
			await insertRaceListing({ provider: 'manual', name: newer, race_date: browserDate(-3) })
		);

		await page.goto('/races');
		await page.getByTestId('races-search').fill(String(stamp));
		await expect(page.getByTestId('races-empty')).toBeVisible({ timeout: 15_000 });

		await page.getByTestId('races-when-recent').click();
		await expect(page.getByTestId('races-when-recent')).toHaveAttribute('aria-pressed', 'true');
		const cards = page.getByTestId('race-card').filter({ hasText: String(stamp) });
		await expect(cards).toHaveCount(2, { timeout: 15_000 });
		await expect(cards.nth(0)).toContainText(newer);
		await expect(cards.nth(1)).toContainText(older);
		await expect(cards.nth(0).getByTestId('race-import')).toBeVisible();

		await page.getByTestId('races-when-upcoming').click();
		await expect(page.getByTestId('races-empty')).toBeVisible({ timeout: 15_000 });
	});
});
