import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';
import { acceptCookieConsent } from '../fixtures/helpers';

test.describe('/explore — authed user', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
	});

	test('redirects to /routes?tab=explore', async ({ page }) => {
		await page.goto('/explore');
		await page.waitForURL(/\/routes\?tab=explore/, { timeout: 10_000 });
		await expect(
			page.getByTestId('routes-view-nav').getByRole('link', { name: 'Explore', exact: true })
		).toHaveAttribute('aria-current', 'true', { timeout: 10_000 });
	});

	test('Explore is the current view post-redirect, on its Routes kind', async ({ page }) => {
		await page.goto('/explore');
		await page.waitForURL(/\/routes\?tab=explore/, { timeout: 10_000 });

		const nav = page.getByTestId('routes-view-nav');
		await expect(nav.getByRole('link')).toHaveCount(2, { timeout: 10_000 });
		await expect(nav.getByRole('link', { name: 'Mine', exact: true })).not.toHaveAttribute(
			'aria-current',
			/.+/
		);
		await expect(
			page.getByTestId('routes-explore-kind').getByRole('link', { name: 'Routes', exact: true })
		).toHaveAttribute('aria-current', 'page');
	});

	test('Explore content (RouteExplorer) mounts after the redirect', async ({ page }) => {
		await page.goto('/explore');
		await page.waitForURL(/\/routes\?tab=explore/, { timeout: 10_000 });
		await expect(page.getByTestId('routes-explore-kind')).toBeVisible({ timeout: 10_000 });
		await expect(
			page.getByTestId('routes-view-nav').getByRole('link', { name: 'Mine', exact: true })
		).toBeVisible();
	});

	test('post-redirect URL preserves no extra query params', async ({ page }) => {
		await page.goto('/explore');
		await page.waitForURL(/\/routes\?tab=explore/, { timeout: 10_000 });
		const url = new URL(page.url());
		expect(url.pathname).toBe('/routes');
		expect(url.searchParams.get('tab')).toBe('explore');
	});
});

test.describe('/explore — anon visitor', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
	});

	test('anon visitor bounces through the auth wall to /login with return_to', async ({ page }) => {
		await page.goto('/explore');
		await expect(page).toHaveURL(/\/login(\?|$)/, { timeout: 10_000 });

		const url = new URL(page.url());
		const returnTo = url.searchParams.get('return_to');
		if (returnTo) {
			expect(returnTo).toMatch(/\/(explore|routes)/);
		}
	});
});
