import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * /gym/routines holds its layout with a skeleton while the list loads
 * (decisions § 2288) — placeholder routine rows where the routine rows will
 * stand, plus one visually-hidden `role="status"` line announcing the load.
 *
 * /gym/routines is the cheapest page to hold in its loading branch: `loading`
 * stays true until `fetchGymRoutinesWithError` resolves. We stall the
 * gym_routines GET so the branch never advances, assert the skeleton, then
 * release (abort) the request so the page settles and the context tears down
 * clean.
 */
test.describe('/gym/routines loading skeleton', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('shows routine-shaped placeholder rows while data is in flight', async ({ page }) => {
		let releaseGate: () => void = () => {};
		const gate = new Promise<void>((resolve) => {
			releaseGate = resolve;
		});

		// Hold the routines fetch open so the page can't leave its loading
		// branch. Non-GET (or a retry) falls through untouched.
		await page.route('**/rest/v1/gym_routines**', async (route) => {
			if (route.request().method() !== 'GET') {
				await route.fallback();
				return;
			}
			await gate;
			await route.abort();
		});

		await page.goto('/gym/routines');

		const skeleton = page.getByTestId('routine-skeleton');
		await expect(skeleton).toBeVisible({ timeout: 10_000 });
		await expect(skeleton).toHaveAttribute('aria-hidden', 'true');
		await expect(skeleton.locator('li')).toHaveCount(4);
		// The header (title + New routine) is already on screen above it, so
		// the skeleton fills the list area rather than replacing the page.
		await expect(page.getByTestId('routine-new')).toBeVisible();
		// Scoped by text: the root layout keeps a second, permanently-present
		// `role="status"` live region for the undo bar.
		await expect(page.getByRole('status').filter({ hasText: 'Loading…' })).toHaveCount(1);

		releaseGate();
		await expect(skeleton).toHaveCount(0, { timeout: 10_000 });
	});
});
