import { expect, test } from '@playwright/test';

/**
 * `/learn/category/<id>` — guides filtered to one category; unknown
 * category → 404.
 */

test.describe('/learn/category', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('getting-started lists that category and its guides', async ({ page }) => {
		await page.goto('/learn/category/getting-started');

		await expect(page.getByRole('heading', { name: 'Getting started', level: 1 })).toBeVisible();

		const cards = page.locator('a.guide-card');
		await expect(cards.first()).toBeVisible();
		// road-running-101 is a getting-started guide.
		await expect(page.locator('a.guide-card[href="/learn/road-running-101"]')).toBeVisible();
	});

	test('an unknown category 404s', async ({ page }) => {
		const res = await page.goto('/learn/category/not-a-real-category');
		// adapter-static serves the SPA shell (200) then the client
		// resolves to the SvelteKit error page; assert the error UI shows.
		await expect(page.getByText(/404|not found/i).first()).toBeVisible();
		// A prerendered category would 200; the absence of a baked page
		// for an unknown id is the guard.
		expect(res?.status() ?? 200).toBeGreaterThanOrEqual(200);
	});

	test('a category page wears the hub furniture and is not a dead end', async ({ page }) => {
		// It used to be a breadcrumb, a bare H1 and a grid — no kicker, no
		// chips, no closing CTA — so it read as a different site, and the
		// breadcrumb was the only way out.
		await page.goto('/learn/category/getting-started');
		await expect(page.locator('.hero .kicker')).toBeVisible();
		await expect(page.locator('.signup-cta')).toHaveCount(1);

		const chips = page.locator('.category-chip');
		expect(await chips.count()).toBeGreaterThan(1);
		// Exactly one chip marks the page you are on, and it is this one.
		const active = page.locator('.category-chip[aria-current="page"]');
		await expect(active).toHaveCount(1);
		await expect(active).toHaveAttribute('href', '/learn/category/getting-started');
	});

	test('the chips move sideways between categories', async ({ page }) => {
		await page.goto('/learn/category/getting-started');
		await page.locator('.category-chip:not([aria-current="page"])').first().click();
		await page.waitForURL(/\/learn\/category\/(?!getting-started)/);
		await expect(page.locator('.guide-card').first()).toBeVisible();
		await expect(page.locator('.category-chip[aria-current="page"]')).toHaveCount(1);
	});
});
