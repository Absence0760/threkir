import { expect, test } from '@playwright/test';

/**
 * `/learn/<slug>` — a single prerendered guide article.
 */

test.describe('/learn/road-running-101 (article)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('renders the article body, breadcrumb, and CTA block', async ({ page }) => {
		await page.goto('/learn/road-running-101');

		await expect(page.getByRole('heading', { name: 'Road running 101', level: 1 })).toBeVisible();
		// A known prose marker from the body.
		await expect(page.getByText('What road running actually is')).toBeVisible();

		// Breadcrumb up to the hub.
		const breadcrumb = page.getByRole('navigation', { name: 'Breadcrumb' });
		await expect(breadcrumb.getByRole('link', { name: 'Learn' })).toBeVisible();

		// The end-of-article CTA card.
		await expect(
			page.getByRole('heading', { name: 'Ready to do this in the app?' })
		).toBeVisible();
	});

	test('feature CTA points at its app route and the sign-up link is the signup variant', async ({
		page,
	}) => {
		await page.goto('/learn/road-running-101');

		// road-running-101's cta.feature is training-plans → /plans/new.
		await expect(page.getByRole('link', { name: 'Build a training plan' })).toHaveAttribute(
			'href',
			'/plans/new'
		);
		await expect(
			page.getByRole('link', { name: 'Create a free account' })
		).toHaveAttribute('href', '/login?signup=1');
	});

	test('an article ends with more guides to read, not just a CTA', async ({ page }) => {
		// A guide whose only exit is the CTA is a dead end for a reader who
		// wants a second one.
		await page.goto('/learn/road-running-101');
		const related = page.locator('.related .guide-card');
		await expect(related).toHaveCount(3);
		// Never itself.
		for (const href of await related.evaluateAll((els) =>
			els.map((el) => el.getAttribute('href'))
		)) {
			expect(href).not.toBe('/learn/road-running-101');
		}
		// Nearest first: a same-category guide leads.
		await expect(related.first().locator('.category-pill')).toHaveText(/getting started/i);
	});

	test('the article header states a reading time beside the updated date', async ({ page }) => {
		await page.goto('/learn/road-running-101');
		await expect(page.locator('.updated')).toContainText(/min read/i);
	});
});
