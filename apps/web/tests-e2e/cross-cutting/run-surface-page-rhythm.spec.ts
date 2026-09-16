import { expect, test, type Page } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * The five run-surface tabs (Runs / Routes / Segments / Plans / Races) are one
 * strip the user walks left to right, so the strip itself must not move or
 * resize as they walk it. That holds only while every one of the five pages
 * wraps its content in the shared `.page` rhythm — `padding: var(--page-padding-y)
 * var(--page-padding-x)` and nothing else. `/segments` wrapped itself in a
 * 900 px centred `.catalogue` column instead, which shifted the strip 118 px
 * inward and shrank it by 236 px on the one tab of the five, and shrank its
 * `h1` to 1.4rem while the other four sat at the browser default.
 *
 * Measured as an equality across the five, not against pixel literals: the
 * gutter is a token that narrows at 40rem (app.css), so a literal would pin the
 * token's value rather than the thing that matters, which is that all five
 * agree.
 */

const RUN_SURFACES = ['/runs', '/routes', '/segments', '/plans', '/races'];

/**
 * `/segments` is world-readable and renders before auth resolves, so for one
 * frame its strip is laid out against a page that has no sidebar yet — 48/1184
 * where the settled value is 288/944. Wait on the sidebar, which is the element
 * whose arrival moves the content, rather than on the strip alone.
 */
async function stripRect(page: Page, route: string) {
	await page.goto(route);
	await expect(page.locator('nav.sidebar')).toBeVisible({ timeout: 10_000 });
	const strip = page.locator('nav.surface-tabs');
	await expect(strip).toBeVisible({ timeout: 10_000 });
	return strip.evaluate((el) => {
		const r = el.getBoundingClientRect();
		return { x: Math.round(r.x), width: Math.round(r.width) };
	});
}

test.describe('run-surface pages share one page rhythm', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('the surface-tab strip has the same geometry on all five tabs', async ({ page }) => {
		const [first, ...rest] = RUN_SURFACES;
		const baseline = await stripRect(page, first);
		expect(baseline.width, `${first} laid out no strip to compare against`).toBeGreaterThan(0);

		for (const route of rest) {
			expect(await stripRect(page, route), `${route} vs ${first}`).toEqual(baseline);
		}
	});

	test('/segments/[id] sits at the same gutter as the catalogue it came from', async ({
		page
	}) => {
		await page.goto('/segments');
		await expect(page.locator('nav.sidebar')).toBeVisible({ timeout: 10_000 });
		const listX = await page
			.locator('h1')
			.first()
			.evaluate((el) => Math.round(el.getBoundingClientRect().x));

		await page.getByTestId('segment-catalogue-list').locator('a.card').first().click();
		await page.waitForURL(/\/segments\/[0-9a-f-]{36}$/, { timeout: 10_000 });
		await expect(page.locator('nav.sidebar')).toBeVisible({ timeout: 10_000 });

		const detail = page.locator('a.back-link');
		await expect(detail).toBeVisible({ timeout: 10_000 });
		const detailX = await detail.evaluate((el) => Math.round(el.getBoundingClientRect().x));

		expect(detailX).toBe(listX);
	});

	test('the page title renders at the same size on every tab that has one', async ({ page }) => {
		// /runs, /routes and /plans carry their title in the tab strip and have
		// no visible h1 of their own (/runs' is visually-hidden), so only the two
		// that render one are compared.
		const sizes: Record<string, string> = {};

		for (const route of ['/segments', '/races']) {
			await page.goto(route);
			const h1 = page.locator('h1').first();
			await expect(h1).toBeVisible({ timeout: 10_000 });
			sizes[route] = await h1.evaluate((el) => getComputedStyle(el).fontSize);
		}

		expect(sizes['/segments']).toBe(sizes['/races']);
	});
});
