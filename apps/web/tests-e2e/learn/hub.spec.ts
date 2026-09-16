import { expect, test } from '@playwright/test';

/**
 * `/learn` — the anonymous, prerendered Learn hub.
 *
 * Reachable without auth (shell-less + anon-allowed in +layout.svelte).
 * Lists guide cards grouped by category; each card links to a guide
 * article that resolves (no 404).
 */

test.describe('/learn (hub)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor sees the hub heading + at least one guide card', async ({ page }) => {
		await page.goto('/learn');

		await expect(page.getByRole('heading', { name: 'Learn to run', level: 1 })).toBeVisible();

		const firstCard = page.locator('a.guide-card').first();
		await expect(firstCard).toBeVisible();
	});

	test('a guide card links to a guide article that resolves', async ({ page }) => {
		await page.goto('/learn');

		const firstCard = page.locator('a.guide-card').first();
		const href = await firstCard.getAttribute('href');
		expect(href).toMatch(/^\/learn\/[a-z0-9-]+$/);

		await firstCard.click();
		await expect(page).toHaveURL(/\/learn\/[a-z0-9-]+$/);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
	});

	test('the hub is one grid with a start-here guide, not a section per category', async ({
		page,
	}) => {
		// Five of the seven categories hold a single guide, so a section each
		// left a heading, one card, and an auto-fill grid whose other tracks
		// stayed empty. Every guide now sits in one grid behind one promoted
		// entry point.
		await page.goto('/learn');
		await expect(page.locator('.featured-section .guide-card.featured')).toHaveCount(1);
		const cards = page.locator('.guide-card');
		expect(await cards.count()).toBeGreaterThan(4);
		// One grid, not one per category.
		await expect(page.locator('main .guide-grid')).toHaveCount(1);
	});

	test('category chips link to every category page', async ({ page }) => {
		// The per-category browse the section headings used to carry. Each
		// chip must resolve — a chip pointing at an unknown category 404s.
		await page.goto('/learn');
		const chips = page.locator('.category-chip');
		const count = await chips.count();
		expect(count).toBeGreaterThan(0);
		for (let i = 0; i < count; i++) {
			await expect(chips.nth(i)).toHaveAttribute('href', /^\/learn\/category\/[a-z-]+$/);
		}
		await chips.first().click();
		await page.waitForURL(/\/learn\/category\//);
		await expect(page.locator('.guide-card').first()).toBeVisible();
	});

	test('every card states a reading time', async ({ page }) => {
		await page.goto('/learn');
		const cards = page.locator('.guide-card');
		const times = page.locator('.guide-card .reading-time');
		expect(await times.count()).toBe(await cards.count());
		// A real estimate, never the "0 min" an empty count would render.
		for (const text of await times.allTextContents()) {
			expect(text).toMatch(/[1-9]\d*/);
		}
	});
});
