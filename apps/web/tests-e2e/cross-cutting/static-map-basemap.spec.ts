import { expect, test } from '../fixtures/mock-route';
import type { MockRoute } from '../fixtures/mock-route';
import type { Page } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * A list thumbnail requests the basemap the live maps resolve (decisions
 * § 1749). Both previews used to ask MapTiler for a hard-coded `streets-v2`
 * whatever the theme or the runner's `map_style`, while the mobile twin
 * hard-coded `streets-v2-dark` — a dark street map in a light-theme list.
 *
 * With no `map_style` set, `streets` follows the colour scheme, so the two
 * schemes must request the two street slugs. The unit suite
 * (`static_map.test.ts`) pins every style × theme; this pins that the card
 * actually reaches the shared resolver with the page's real scheme.
 *
 * The key is injected and consent accepted the same way
 * `static-map-fallback.spec.ts` does, and every MapTiler request is aborted —
 * only its URL is under test, and the SVG fallback keeps the card intact.
 */

const MAPTILER_HOST = 'api.maptiler.com';

async function recordStaticMapRequests(mockRoute: MockRoute, page: Page): Promise<string[]> {
	const urls: string[] = [];
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
					env: { ...value.env, PUBLIC_MAPTILER_KEY: 'e2e-static-map-basemap' }
				};
			}
		});
	});
	await mockRoute(
		page,
		(url) => url.hostname === MAPTILER_HOST && url.pathname.includes('/static/'),
		async (route) => {
			urls.push(route.request().url());
			await route.abort('failed');
		}
	);
	return urls;
}

// Asserted as "never the OTHER street map" rather than "exactly this slug":
// settings/preferences.spec.ts flips USER_A's map_style to satellite and back
// while other files run, and a satellite request is still a correct one. The
// defect is a street map of the wrong luminance, which this rules out.
for (const [scheme, wrong] of [
	['light', 'streets-v2-dark'],
	['dark', 'streets-v2']
] as const) {
	test.describe(`route thumbnails under a ${scheme} colour scheme`, () => {
		test.use({ storageState: USER_A.storageStatePath, colorScheme: scheme });

		test(`never request the ${wrong} street map`, async ({ page, mockRoute }) => {
			const urls = await recordStaticMapRequests(mockRoute, page);
			await page.goto('/routes');
			await expect(page.locator('.route-card').first()).toBeVisible();

			await expect.poll(() => urls.length).toBeGreaterThan(0);
			for (const url of urls) {
				const { pathname } = new URL(url);
				expect(pathname).toMatch(/^\/maps\/[a-z0-9-]+\/static\//);
				expect(pathname.startsWith(`/maps/${wrong}/`), pathname).toBe(false);
			}
		});
	});
}
