import { expect, test } from '../fixtures/mock-route';

import { USER_A } from '../fixtures/users';

/**
 * /nutrition — a SECONDARY data-load failure must surface, not render as an
 * empty page (uxhunt-web.md finding #2).
 *
 * The page loads today's food (primary, already covered by nutrition.spec.ts),
 * then the 7-day trend window, templates, and recipes. The week-trend fetch
 * previously swallowed its error and returned an empty list — so a transient
 * failure left the trend chart blank, indistinguishable from a week with
 * nothing logged. It now flows through fetchFoodLogWithError and surfaces the
 * same load-error banner + Retry the primary path uses.
 *
 * We let the FIRST food_log GET (today) succeed and fail the SECOND (the week
 * window), proving it's the secondary load — not the primary — that trips the
 * banner. Retry (a fresh load) recovers.
 */
test.describe('/nutrition — secondary load failure surfaces', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed week-trend load shows the error banner, not an empty page', async ({
		page,
		mockRoute
	}) => {
		let foodLogGets = 0;
		await mockRoute(page, '**/rest/v1/food_log**', async (route) => {
			// The layout's once-per-session Nutrition visibility probe
			// (`select=id … limit=1`, decisions § 1739 amendment) reads food_log
			// too, at a time of its own. It is not one of the page's loads, so it
			// must not shift the ordinal that picks out the week window.
			const url = route.request().url();
			const isVisibilityProbe = url.includes('select=id&') && url.includes('limit=1');
			if (route.request().method() === 'GET' && !isVisibilityProbe) {
				foodLogGets += 1;
				// #1 = today (primary, must succeed); #2 = the 7-day trend window.
				if (foodLogGets === 2) {
					await route.fulfill({
						status: 500,
						contentType: 'application/json',
						body: JSON.stringify({ message: 'simulated week-trend failure' }),
					});
					return;
				}
			}
			await route.fallback();
		});

		await page.goto('/nutrition');

		const banner = page.getByTestId('nutrition-load-error');
		await expect(banner).toBeVisible({ timeout: 10_000 });
		// The misleading "nothing logged" empty state must NOT be what a
		// transient secondary failure renders as.
		await expect(page.getByTestId('macro-rings-empty')).toHaveCount(0);

		// Retry issues a fresh load; the week fetch (now the 4th GET) succeeds.
		await page.getByRole('button', { name: 'Retry' }).click();
		await expect(banner).toHaveCount(0, { timeout: 10_000 });
	});
});
