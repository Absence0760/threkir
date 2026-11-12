import { expect, test } from '../fixtures/test';

/**
 * `/learn/park-courses-how-timing-works` — the public explainer for park
 * courses (issue #1313). Pins its SEO head and that its prose and its CTA
 * send the reader to the park course catalogue.
 */

const SLUG = 'park-courses-how-timing-works';

test.describe(`/learn/${SLUG}`, () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('title, canonical, Open Graph, and Article JSON-LD are present', async ({ page }) => {
		await page.goto(`/learn/${SLUG}`);

		await expect(page).toHaveTitle(/Park courses: how timing works — Threkir/);

		const canonicalHref = await page.locator('link[rel="canonical"]').getAttribute('href');
		expect(canonicalHref).toMatch(new RegExp(`^https?://.+/learn/${SLUG}$`));

		expect(await page.locator('meta[property="og:title"]').getAttribute('content')).toContain(
			'Park courses: how timing works',
		);
		expect(await page.locator('meta[property="og:type"]').getAttribute('content')).toBe('article');
		expect(
			await page.locator('meta[property="og:description"]').getAttribute('content'),
		).toContain('checkpoints');

		const ld = JSON.parse(
			(await page.locator('script[type="application/ld+json"]').first().textContent()) as string,
		);
		expect(ld['@type']).toBe('Article');
		expect(ld.headline).toBe('Park courses: how timing works');
	});

	test('explains seasons in the park time zone and links to the catalogue', async ({ page }) => {
		await page.goto(`/learn/${SLUG}`);

		await expect(page.getByRole('heading', { level: 1 })).toHaveText('Park courses: how timing works');
		await expect(page.getByRole('heading', { name: /Seasons follow the park.s clock/ })).toBeVisible();
		const link = page.locator('article').getByRole('link', { name: 'park courses' });
		await expect(link).toHaveAttribute('href', '/parks');
		// The end-of-article CTA (cta.feature: parks) points at the same catalogue.
		await expect(page.getByRole('link', { name: 'Find a park course' })).toHaveAttribute(
			'href',
			'/parks',
		);
	});
});
