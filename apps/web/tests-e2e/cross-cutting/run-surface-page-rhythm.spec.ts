import type { Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * The run surface (Runs / Plans / Races & courses / Routes, plus /segments,
 * which marks Routes) is one title row and one strip the user walks left to
 * right, so neither may move or resize as they walk it. That holds only while
 * every page wraps its content in the shared `.page` rhythm — `padding:
 * var(--page-padding-y) var(--page-padding-x)` and nothing else — and renders
 * nothing above `RunSurfaceTabs`. `/segments` once wrapped itself in a 900 px
 * centred `.catalogue` column, which shifted the strip 118 px inward and shrank
 * it by 236 px on that one tab; and while Races & courses and Segments put a
 * title of their own under the strip, the content below it started lower on
 * those two.
 *
 * Measured as an equality across the pages, not against pixel literals: the
 * gutter is a token that narrows at 40rem (app.css), so a literal would pin the
 * token's value rather than the thing that matters, which is that all agree.
 * The title and the strip sit in one block inside `RunSurfaceTabs`, so the
 * host page's flex gap cannot move one against the other.
 */

const RUN_SURFACES = ['/runs', '/plans', '/races', '/routes', '/segments'];

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
		return { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width) };
	});
}

test.describe('run-surface pages share one page rhythm', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
	});

	// Five pages, four tabs: `/segments` is Routes → Explore → Segments since
	// issue #1374 and carries the title and the strip with Routes marked.
	test('the surface-tab strip has the same geometry on every run-surface page', async ({ page }) => {
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
		// The catalogue's left edge is the run surface's title, which starts
		// at the page gutter.
		const listX = await page
			.getByTestId('run-surface-header')
			.getByRole('heading', { level: 1 })
			.evaluate((el) => Math.round(el.getBoundingClientRect().x));

		await page.getByTestId('segment-catalogue-list').getByRole('link').first().click();
		await page.waitForURL(/\/segments\/[0-9a-f-]{36}$/, { timeout: 10_000 });
		await expect(page.locator('nav.sidebar')).toBeVisible({ timeout: 10_000 });

		const detail = page.locator('a.back-link');
		await expect(detail).toBeVisible({ timeout: 10_000 });
		const detailX = await detail.evaluate((el) => Math.round(el.getBoundingClientRect().x));

		expect(detailX).toBe(listX);
	});

	// The one title is the strip's, so its h1 and each tab's primary action
	// (the web analogue of the mobile root's FAB) sit on the same row at the
	// same height on every tab. /segments has no primary action of its own.
	test('the title and the primary action sit at the same height on every tab', async ({ page }) => {
		const ACTIONS: Record<string, string> = {
			'/runs': '[data-testid="runs-add"]',
			'/plans': '[data-testid="plans-new"]',
			'/races': '[data-testid="race-submit"]',
			'/routes': '[data-testid="routes-new"]'
		};
		const titles: Record<string, { x: number; y: number }> = {};
		const actions: Record<string, number> = {};
		for (const route of RUN_SURFACES) {
			await page.goto(route);
			await expect(page.locator('nav.sidebar')).toBeVisible({ timeout: 10_000 });
			const header = page.getByTestId('run-surface-header');
			const h1 = header.getByRole('heading', { level: 1 });
			await expect(h1).toBeVisible({ timeout: 10_000 });
			await expect(page.getByRole('heading', { level: 1 })).toHaveCount(1);
			titles[route] = await h1.evaluate((el) => {
				const r = el.getBoundingClientRect();
				return { x: Math.round(r.x), y: Math.round(r.y) };
			});
			const selector = ACTIONS[route];
			if (!selector) continue;
			const action = header.locator(selector);
			await expect(action, `${route} has no primary action on its title row`).toBeVisible({
				timeout: 10_000
			});
			actions[route] = await action.evaluate((el) => Math.round(el.getBoundingClientRect().y));
		}

		for (const route of RUN_SURFACES.slice(1)) {
			expect(titles[route], `${route} title vs /runs`).toEqual(titles['/runs']);
		}
		for (const route of Object.keys(ACTIONS).slice(1)) {
			expect(actions[route], `${route} primary action vs /runs`).toBe(actions['/runs']);
		}
	});
});
