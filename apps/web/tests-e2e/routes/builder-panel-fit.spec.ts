import { expect, test, type Page } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /routes/new — the sidebar panel must fit what it holds.
 *
 * The builder's sidebar is a resizable SplitPane pane whose lower bound
 * is 280px, and two of its rows are flex rows of labelled buttons: the
 * waypoint toolbar (Add point / Undo / Out & back / Clear) and the
 * primary actions (Save Route / GPX / KML). A flex item's `min-width`
 * is `auto`, so `flex: 1` does not let a labelled button shrink below
 * its icon+label min-content width — the row overflows instead. When
 * the toolbar grew its fourth button the row needed 379px inside a
 * 242px content box: Clear rendered entirely off the panel edge and the
 * panel scrolled sideways, which is what a user reported as the page
 * having "regressed badly".
 *
 * Nothing about that is visible to a test that only asserts a button
 * exists — `toBeVisible()` passes on a clipped button — so the contract
 * is measured: every row's scrollWidth fits its clientWidth, at the
 * default split and at the narrowest the pane can be dragged.
 */

const ROWS = ['.toolbar-group', '.primary-actions'] as const;

async function overflowByRow(page: Page): Promise<Record<string, number>> {
	return page.evaluate((selectors) => {
		const out: Record<string, number> = {};
		for (const sel of selectors) {
			const el = document.querySelector(sel);
			if (!el) throw new Error(`row not found: ${sel}`);
			out[sel] = el.scrollWidth - el.clientWidth;
		}
		return out;
	}, ROWS as unknown as string[]);
}

test.describe('/routes/new — sidebar rows fit the pane', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('waypoint toolbar + primary actions never overflow at the default split', async ({
		page
	}) => {
		await page.goto('/routes/new');
		await expect(page.getByRole('heading', { name: 'Route Builder', level: 1 })).toBeVisible({
			timeout: 10_000
		});

		expect(await overflowByRow(page)).toEqual({
			'.toolbar-group': 0,
			'.primary-actions': 0
		});

		// Every button in the toolbar is inside the pane's box, not just
		// in the DOM — a clipped button still reports as visible. The pane
		// is `.split-left`, not `.sidebar`: the app shell's nav carries
		// that class too, so `.sidebar` is ambiguous here.
		const panel = await page.locator('.split-left').boundingBox();
		expect(panel).not.toBeNull();
		const buttons = page.locator('.toolbar-group .btn');
		await expect(buttons).toHaveCount(4);
		for (let i = 0; i < 4; i++) {
			const box = await buttons.nth(i).boundingBox();
			expect(box).not.toBeNull();
			expect(box!.x + box!.width).toBeLessThanOrEqual(panel!.x + panel!.width + 1);
		}
	});

	test('rows still fit when the pane is dragged to the SplitPane minimum', async ({ page }) => {
		// 280px is `min` on the SplitPane in +page.svelte — the narrowest
		// the user can drag the panel, and so the worst case the rows have
		// to survive. Seeded through the same localStorage key the drag
		// persists to, before the first navigation so the pane mounts at
		// that width rather than resizing after paint.
		await page.addInitScript(() => localStorage.setItem('route-builder-split', '280'));

		await page.goto('/routes/new');
		await expect(page.getByRole('heading', { name: 'Route Builder', level: 1 })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.locator('.split-left')).toHaveAttribute('style', /width:\s*280px/);

		expect(await overflowByRow(page)).toEqual({
			'.toolbar-group': 0,
			'.primary-actions': 0
		});
	});
});

test.describe('/routes/new — "use my location" before the map is consented', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ page, context }) => {
		// Reject rather than clear: the map stays behind its consent card
		// either way, but a pending choice also floats the cookie banner
		// over the sidebar. Must run before goto — consent.svelte.ts reads
		// localStorage once on first import.
		await page.addInitScript(() =>
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'rejected', timestamp: Date.now() })
			)
		);
		await context.grantPermissions(['geolocation']);
		await context.setGeolocation({ latitude: 51.5074, longitude: -0.1278 });
	});

	test('tells the user to load the map instead of silently doing nothing', async ({ page }) => {
		await page.goto('/routes/new');
		await expect(page.getByTestId('route-builder-consent')).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		await page.getByRole('button', { name: 'Use my location for start' }).click();

		// The fix: flyTo reports that there was no map to move, and the
		// page says so. Before it, the recentre was swallowed and the only
		// feedback was a label change further up a scrolling panel — the
		// button read as dead.
		await expect(page.getByText('Found your location. Load the map to see it.')).toBeVisible({
			timeout: 10_000
		});
		// The point itself is still captured, so Generate is usable.
		await expect(page.locator('.point-set').first()).toHaveText('My location');
	});
});
