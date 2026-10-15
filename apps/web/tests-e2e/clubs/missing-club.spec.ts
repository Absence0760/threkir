import type { Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * /social?tab=clubs Browse — "Is your club missing? Set it up" (issue #1151
 * step 5). A search that finds nothing is the moment a runner learns their
 * club is not on the app yet, so the empty state offers to set it up (the
 * create form, prefilled with what they searched for) and links the
 * create-a-club help guide. A failed search is not "nothing found" and must
 * not offer it.
 */

const NO_GEOCODE = { type: 'FeatureCollection', features: [] };

const uniqueName = (prefix: string): string =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

async function stubGeocoding(page: Page): Promise<void> {
	await page.route('**/api.maptiler.com/geocoding/**', (route) =>
		route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(NO_GEOCODE) }),
	);
}

async function searchBrowse(page: Page, query: string): Promise<void> {
	await page.goto('/social?tab=clubs&clubs-sub=browse');
	await page.getByPlaceholder(/Search by name/).fill(query);
}

test.describe('clubs Browse — missing club', () => {
	test.describe('signed in', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('a search that finds nothing offers to set the club up, prefilled, plus the guide', async ({
			page,
		}) => {
			await stubGeocoding(page);
			const query = uniqueName('Nowhere Harriers & AC');
			await searchBrowse(page, query);

			await expect(page.getByRole('heading', { name: `No clubs match "${query}"` })).toBeVisible({
				timeout: 10_000,
			});
			await expect(page.getByText(/Is your club missing\? It may not be on Threkir yet/)).toBeVisible();

			const setUp = page.getByRole('link', { name: 'Set up your club' });
			await expect(setUp).toHaveAttribute('href', `/clubs/new?name=${encodeURIComponent(query)}`);
			await expect(page.getByRole('link', { name: 'How to create a club' })).toHaveAttribute(
				'href',
				'/help/create-a-club',
			);

			await setUp.click();
			await page.waitForURL(/\/clubs\/new\?name=/, { timeout: 10_000 });
			await expect(page.getByRole('textbox', { name: 'Name', exact: true })).toHaveValue(query);
		});

		test('the guide link opens the create-a-club help guide', async ({ page }) => {
			await stubGeocoding(page);
			await searchBrowse(page, uniqueName('Guide Hunt'));

			await page.getByRole('link', { name: 'How to create a club' }).click();
			await page.waitForURL(/\/help\/create-a-club$/, { timeout: 10_000 });
			await expect(page.getByRole('heading', { level: 1, name: 'Create a club' })).toBeVisible();
		});

		test('a failed search shows the error card and does not offer to set a club up', async ({
			page,
		}) => {
			await stubGeocoding(page);
			const fail = (route: import('@playwright/test').Route) =>
				route.request().method() === 'GET'
					? route.fulfill({
							status: 500,
							contentType: 'application/json',
							body: JSON.stringify({ message: 'simulated clubs failure' }),
						})
					: route.continue();
			await page.route('**/rest/v1/rpc/search_clubs*', fail);
			await page.route('**/rest/v1/clubs*', fail);

			// The unfiltered Browse load fails first; wait for the search's own
			// request so the assertions read the settled search, not that card.
			const searched = page.waitForResponse((r) => r.url().includes('/rest/v1/rpc/search_clubs'));
			await searchBrowse(page, uniqueName('Broken Search'));
			await searched;

			await expect(page.getByText("Couldn't load clubs")).toBeVisible({ timeout: 10_000 });
			await expect(page.getByRole('link', { name: 'Set up your club' })).toHaveCount(0);
			await expect(page.getByTestId('clubs-missing-club')).toHaveCount(0);
		});
	});

	test.describe('signed out', () => {
		test('the set-up link sends a visitor through sign-in and back to the prefilled form', async ({
			page,
		}) => {
			await page.addInitScript(() => {
				localStorage.setItem('cookie_consent', JSON.stringify({ choice: 'accepted', timestamp: Date.now() }));
			});
			const name = 'Lakeside Joggers';
			const target = `/clubs/new?name=${encodeURIComponent(name)}`;

			await page.goto(target);
			await page.waitForURL(/\/login\?return_to=/, { timeout: 10_000 });
			expect(new URL(page.url()).searchParams.get('return_to')).toBe(target);

			await page.waitForLoadState('networkidle');
			await page.locator('input[type="email"]').fill(USER_A.email);
			await page.locator('input[type="password"]').fill(USER_A.password);
			await page.locator('form button[type="submit"]').click();

			await page.waitForURL((url) => url.pathname === '/clubs/new', { timeout: 15_000 });
			await expect(page.getByRole('textbox', { name: 'Name', exact: true })).toHaveValue(name);
		});
	});
});
