import { expect, test } from '../fixtures/mock-route';
import type { MockRoute } from '../fixtures/mock-route';
import type { Page } from '@playwright/test';

import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * A static-map outage must not break the card it decorates (issue #902).
 *
 * The map image is an L3 layer over an L1 card (conventions.md § Layered
 * resilience). The thumbnails used to fall back to the SVG track preview only
 * when no URL could be BUILT — no key, or fewer than two points — and never
 * when the request itself failed, so a MapTiler outage rendered a wall of
 * broken images across /routes, /runs, the feed and public profiles.
 *
 * The e2e server boots with no MapTiler key, which is exactly the case the old
 * code already handled, so the spec has to put the image on the page before it
 * can take the image away. `$env/dynamic/public` is `__sveltekit_dev.env` on a
 * dev-server client, assigned by the document's inline bootstrap script, so an
 * init script traps that assignment and adds a key. Rewriting the document
 * instead would not work: Chromium treats a fulfilled document as outside the
 * loopback address space and blocks every request it makes to local Supabase.
 * The spec then accepts the cookie banner the MapTiler branch waits for, and
 * aborts every MapTiler request.
 *
 * The abort counter is load-bearing: without it, a SvelteKit change to the
 * bootstrap global would leave no key on the page, render the SVG for the old
 * reason, and pass without ever exercising a failed request.
 */

const MAPTILER_HOST = 'api.maptiler.com';

async function simulateStaticMapOutage(mockRoute: MockRoute, page: Page): Promise<{ aborted: () => number }> {
	let aborted = 0;
	await page.addInitScript(() => {
		localStorage.setItem(
			'cookie_consent',
			JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
		);
		let bootstrap: { env: Record<string, string> } | undefined;
		Object.defineProperty(window, '__sveltekit_dev', {
			configurable: true,
			get: () => bootstrap,
			set: (value: { env: Record<string, string> }) => {
				bootstrap = {
					...value,
					env: { ...value.env, PUBLIC_MAPTILER_KEY: 'e2e-static-map-outage' }
				};
			}
		});
	});
	await mockRoute(page, 
		(url) => url.hostname === MAPTILER_HOST,
		async (route) => {
			aborted++;
			await route.abort('failed');
		}
	);
	return { aborted: () => aborted };
}

/** A lazy image still waiting for the viewport is neither complete nor broken. */
async function brokenImages(page: Page, scope: string): Promise<number> {
	return page
		.locator(`${scope} img`)
		.evaluateAll(
			(imgs) =>
				(imgs as HTMLImageElement[]).filter((img) => img.complete && img.naturalWidth === 0).length
		);
}

const DEG_PER_M_LAT = 1 / 111_320;

function straightTrack() {
	const t0 = Date.now() - 30 * 60_000;
	return Array.from({ length: 30 }, (_, i) => ({
		lat: 40 + i * 50 * DEG_PER_M_LAT,
		lng: -105,
		ts: new Date(t0 + i * 20_000).toISOString()
	}));
}

test.describe('static map outage falls back to the SVG track preview', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/routes cards draw the track when the map image fails', async ({ page, mockRoute }) => {
		const outage = await simulateStaticMapOutage(mockRoute, page);
		await page.goto('/routes');
		const cards = page.locator('.route-card');
		await expect(cards.first()).toBeVisible();

		await expect.poll(outage.aborted).toBeGreaterThan(0);
		await expect(cards.first().locator('svg.track-preview')).toBeVisible();
		await expect(cards.first().locator('[data-testid="route-preview-map"]')).toHaveCount(0);
		await expect.poll(() => brokenImages(page, '.route-card')).toBe(0);
	});

	test('/runs cards and the run share card fall back when the map image fails', async ({
		page,
		mockRoute
	}) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 1_450,
			duration_s: 580,
			track: straightTrack()
		});
		try {
			const outage = await simulateStaticMapOutage(mockRoute, page);
			await page.goto('/runs');
			const card = page.locator(`a.run-card[href="/runs/${runId}"]`);
			await expect(card).toBeVisible();

			await expect.poll(outage.aborted).toBeGreaterThan(0);
			await expect(card.locator('svg.track-preview')).toBeVisible();
			await expect(card.locator('[data-testid="run-preview-map"]')).toHaveCount(0);
			await expect.poll(() => brokenImages(page, '.run-card')).toBe(0);

			const before = outage.aborted();
			await page.goto(`/runs/${runId}`);
			await expect(page.locator('.share-card .share-card-stats')).toBeAttached();
			await expect.poll(outage.aborted).toBeGreaterThan(before);
			await expect(page.locator('[data-testid="share-card-map"]')).toHaveCount(0);
			await expect.poll(() => brokenImages(page, '.share-card')).toBe(0);
		} finally {
			await deleteRun(runId);
		}
	});
});
