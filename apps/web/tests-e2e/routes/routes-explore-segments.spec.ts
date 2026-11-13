import { expect, test } from '../fixtures/test';

import { acceptCookieConsent } from '../fixtures/helpers';
import { USER_A } from '../fixtures/users';

/**
 * Issue #1374, owner decision 1: the segment catalogue is no longer a
 * run-surface tab. Routes is Mine · Explore, Explore has Routes · Segments,
 * and `/segments` stays its own URL, reached from Routes → Explore and shown
 * with Routes marked in the strip, the same tab names and order as the mobile
 * Fitness hub.
 */
test.describe('Routes → Explore → Segments', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
	});

	test('the strip has no Segments tab and marks Routes on /segments', async ({ page }) => {
		await page.goto('/segments');
		const strip = page.locator('nav.surface-tabs');
		await expect(strip).toBeVisible({ timeout: 10_000 });
		await expect(strip.getByRole('link')).toHaveText(['Runs', 'Plans', 'Races & courses', 'Routes']);
		await expect(strip.getByRole('link', { name: 'Routes', exact: true })).toHaveAttribute(
			'aria-current',
			'page'
		);
		const nav = page.getByTestId('routes-view-nav');
		await expect(nav.getByRole('link', { name: 'Explore', exact: true })).toHaveAttribute(
			'aria-current',
			'true'
		);
		await expect(page.getByTestId('routes-explore-segments')).toHaveAttribute('aria-current', 'page');
		await expect(page.getByTestId('routes-explore-map')).toHaveCount(0);
	});

	test('Explore → Segments opens /segments, and Routes goes back to public routes', async ({ page }) => {
		await page.goto('/routes?tab=explore');
		await page.getByTestId('routes-explore-segments').click();
		await page.waitForURL(/\/segments$/, { timeout: 10_000 });
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible();

		await page
			.getByTestId('routes-explore-kind')
			.getByRole('link', { name: 'Routes', exact: true })
			.click();
		await page.waitForURL(/\/routes\?tab=explore$/, { timeout: 10_000 });
		await expect(page.getByTestId('routes-explore-map')).toBeVisible();
	});

	test('Mine from /segments returns to the route library', async ({ page }) => {
		await page.goto('/segments');
		await page
			.getByTestId('routes-view-nav')
			.getByRole('link', { name: 'Mine', exact: true })
			.click();
		await page.waitForURL(/\/routes$/, { timeout: 10_000 });
		await expect(page.getByTestId('routes-explore-kind')).toHaveCount(0);
	});

	test('at a phone width the view row and the strip stay inside the page', async ({ page }) => {
		await page.setViewportSize({ width: 360, height: 740 });
		await page.goto('/routes?tab=explore');
		await expect(page.getByTestId('routes-explore-kind')).toBeVisible({ timeout: 10_000 });
		const overflow = await page.evaluate(
			() => document.documentElement.scrollWidth - document.documentElement.clientWidth
		);
		expect(overflow, 'the page scrolls sideways').toBeLessThanOrEqual(0);
	});
});
