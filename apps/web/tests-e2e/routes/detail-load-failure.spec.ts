import { expect, test } from '../fixtures/test';

import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /routes/[id] — a failed route read must not claim the route is gone.
 *
 * `fetchRouteById` returned null on a postgrest error the same way it
 * returns null for a row that isn't there, and the page branches on
 * `!route`, so a transient failure told the owner "Route not found — this
 * route may have been deleted." The reader now throws on a failed read and
 * returns null only for a genuine miss, so the page can tell the two apart.
 */
test.describe('/routes/[id] — a failed read is not a missing route', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('shows a load error with retry, not the not-found card', async ({ page }) => {
		let failRead = true;
		// The owner branch reads the base `routes` table; fail that and the
		// public_routes fallback so neither path can quietly answer.
		for (const pattern of ['**/rest/v1/routes?*', '**/rest/v1/public_routes?*']) {
			await page.route(pattern, async (route) => {
				if (failRead && route.request().method() === 'GET') {
					await route.fulfill({
						status: 500,
						contentType: 'application/json',
						body: JSON.stringify({ message: 'simulated route read failure' }),
					});
					return;
				}
				await route.fallback();
			});
		}

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);

		const banner = page.getByTestId('route-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(banner).toHaveAttribute('role', 'alert');
		await expect(page.getByRole('heading', { name: 'Route not found' })).toHaveCount(0);

		// The retry re-reads and resolves onto the real route.
		failRead = false;
		await banner.getByRole('button', { name: 'Retry' }).click();
		await expect(page.getByTestId('route-load-error')).toHaveCount(0, { timeout: 15_000 });
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 15_000 });
	});

	test('a genuinely absent route still gets the not-found card', async ({ page }) => {
		await page.goto('/routes/00000000-0000-4000-8000-000000000000');

		await expect(page.getByRole('heading', { name: 'Route not found' })).toBeVisible({
			timeout: 15_000,
		});
		await expect(page.getByTestId('route-load-error')).toHaveCount(0);
	});
});

/**
 * A non-owner's line comes from the privacy clip (`clip_route_for_viewer`).
 * Its failure used to resolve to `[]`, the same as a route with no line, so
 * the viewer got "No waypoint data available" and nothing to retry. The
 * route's metadata still renders; the map slot says the line failed and
 * offers a retry, and nothing unclipped is ever drawn in its place.
 */
test.describe('/routes/[id] — a failed privacy-clipped line', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('says the line failed, draws no map, and a retry brings the line', async ({
		page,
		mockRoute,
	}) => {
		let failClip = true;
		let clipCalls = 0;
		await mockRoute(page, '**/rest/v1/rpc/clip_route_for_viewer*', async (route) => {
			clipCalls++;
			if (failClip) {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated clip failure' }),
				});
				return;
			}
			await route.fallback();
		});

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 15_000 });

		const failed = page.getByTestId('route-line-failed');
		await expect(failed).toBeVisible({ timeout: 15_000 });
		await expect(failed.getByRole('status')).toHaveText(
			'Couldn’t load the route line. Check your connection and try again.',
		);
		await expect(page.getByText('No waypoint data available')).toHaveCount(0);
		await expect(page.locator('.map-panel .run-map-wrapper')).toHaveCount(0);

		failClip = false;
		const before = clipCalls;
		await failed.getByRole('button', { name: 'Retry' }).click();
		await expect(page.getByTestId('route-line-failed')).toHaveCount(0, { timeout: 15_000 });
		expect(clipCalls).toBeGreaterThan(before);
		await expect(page.locator('.map-panel .run-map-wrapper')).toHaveCount(1, { timeout: 15_000 });
	});
});
