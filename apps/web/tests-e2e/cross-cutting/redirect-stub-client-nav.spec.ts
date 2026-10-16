import type { Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * `/settings` and `/explore` are redirect stubs: an onMount `goto()` for the
 * SPA, plus a `<meta http-equiv="refresh">` for a no-JS cold load. The meta
 * lives in `<svelte:head>`, which also renders on a client-side navigation,
 * and a browser obeys a refresh meta inserted by script -- so reaching either
 * stub from inside the app was a full page reload. Wrapping the meta in
 * `<noscript>` keeps the fallback in the prerendered HTML and out of the live
 * DOM.
 *
 * The probe is a window property set before navigating: it survives a
 * client-side route change and is gone after a document reload.
 */

async function markWindow(page: Page) {
	await page.evaluate(() => {
		(window as unknown as { __noReload?: boolean }).__noReload = true;
	});
}

async function windowSurvived(page: Page): Promise<boolean> {
	return page.evaluate(() => (window as unknown as { __noReload?: boolean }).__noReload === true);
}

/// Retargets the sidebar logo link and clicks it, so the navigation takes the
/// same router path every in-app link does. A freshly created anchor is not a
/// faithful probe: the router does not pick it up, and the click navigates
/// the document itself.
async function clientNavigate(page: Page, href: string) {
	const logo = page.locator('a.logo').first();
	await logo.evaluate((a, target) => a.setAttribute('href', target), href);
	await logo.click();
}

test.describe('redirect stubs navigate client-side', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('dashboard -> account menu Settings does not reload the page', async ({ page }) => {
		await page.goto('/dashboard');
		await markWindow(page);

		await page.locator('.profile-btn').click();
		await page.getByRole('menuitem', { name: 'Settings' }).click();

		await expect(page).toHaveURL(/\/settings\/account$/);
		await expect(page.locator('.settings-nav')).toBeVisible();
		expect(await windowSurvived(page)).toBe(true);
	});

	for (const [stub, landing] of [
		['/settings', /\/settings\/account$/],
		['/explore', /\/routes\?tab=explore$/],
	] as const) {
		test(`${stub} redirects without a document reload`, async ({ page }) => {
			await page.goto('/dashboard');
			await markWindow(page);

			await clientNavigate(page, stub);

			await expect(page).toHaveURL(landing);
			// Give a refresh meta, had one been inserted, time to fire.
			await page.waitForLoadState('networkidle');
			expect(await windowSurvived(page)).toBe(true);
		});
	}
});
