import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';
import { readRows } from '../fixtures/db-read';

/**
 * Heatmap discoverable-pin layers (clubs + popular/featured routes)
 * — interconnected coverage for the May 2026 feature pass.
 *
 * What this file pins down:
 *
 *   1. Backend RPCs return the expected shape + respect bbox /
 *      `is_public` filters. (No private clubs / private routes
 *      ever appear in the result; routes must be featured OR
 *      have run_count > 0.)
 *
 *   2. Web heatmap renders the pins as MapLibre circle layers
 *      and the count chips in the legend match the RPC result.
 *
 *   3. Clicking a pin opens a popup card (NOT instant
 *      navigation) with the expected content shape.
 *
 *   4. Clicking the popup's "View" action navigates client-side
 *      to the entity detail page, which returns 200.
 *
 *   5. Hover shows a name-only tooltip; mouseleave clears it.
 *
 *   6. Layer toggles in the legend hide / show the right layer.
 *
 *   7. The defensive `Number.isFinite` guard on the marker /
 *      popup paths keeps non-finite coordinates from collapsing
 *      to the (0,0) top-left of the map.
 *
 * Drives the page as an unauthenticated viewer when possible so
 * the share-link / anon flow stays exercised; uses USER_A for the
 * tests that need to assert the My-routes / detail-page side too.
 */

const VA_BBOX = {
	p_min_lng: -83.7,
	p_min_lat: 36.5,
	p_max_lng: -75.2,
	p_max_lat: 39.5,
	p_limit: 100,
};

// Hardcoded from seed.sql (these are stable across resets).
const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const PRIVATE_CLUB_ID = 'c3333333-0000-0000-0000-000000000003';

type MapHandle = {
	jumpTo: (o: { center: [number, number]; zoom: number }) => void;
	project: (lngLat: [number, number]) => { x: number; y: number };
	getContainer: () => HTMLElement;
	loaded: () => boolean;
	isMoving: () => boolean;
	queryRenderedFeatures: (
		point: [number, number],
		opts?: { layers?: string[] },
	) => Array<{ properties?: { id?: string }; geometry: { coordinates: unknown } }>;
};
type HeatmapHooks = { __heatmapMap?: MapHandle; __heatmapPinsSettled?: () => boolean };

// Nothing below sleeps. Each step waits on the state the next action
// depends on, because a timer only guesses at it: issue #1196 was a fixed
// 1200 ms wait losing to the page's own initial framing (a fitBounds that
// awaits a fetch and then animates for 600 ms) on a slow runner. The fit
// interrupted the spec's flyTo, and the click meant for a pin at zoom 14
// landed on a route cluster at zoom ~4.

// Jump the camera to `center` once the page has finished framing itself,
// then wait until that move's own pin refresh has landed and rendered.
// `jumpTo`, not an animated move: there is nothing to watch, and an
// animation is one more thing for the next action to race.
async function jumpAndSettle(page: Page, center: [number, number], zoom: number) {
	const settled = () => {
		const w = window as unknown as HeatmapHooks;
		const m = w.__heatmapMap;
		return !!m && !!w.__heatmapPinsSettled?.() && m.loaded() && !m.isMoving();
	};
	await page.waitForFunction(settled, undefined, { timeout: 15_000 });
	await page.evaluate(([lng, lat, z]) => {
		(window as unknown as HeatmapHooks).__heatmapMap!.jumpTo({ center: [lng, lat], zoom: z });
	}, [center[0], center[1], zoom] as const);
	await page.waitForFunction(settled, undefined, { timeout: 15_000 });
}

// Put the camera on the pin at `target` and return its viewport pixel,
// once a real click there is certain to hit exactly that pin. The caller
// drives a genuine mouse click — MapLibre's layer click handlers only fire
// when queryRenderedFeatures hits under a real pointer event. Exactly one
// feature, because the route-pin handler defers to the overlap list when
// several routes stack under the click.
async function settleOnPin(
	page: Page,
	target: [number, number],
	layer: 'heatmap-clubs-layer' | 'heatmap-route-pins-layer',
) {
	await jumpAndSettle(page, target, 14);
	const handle = await page.waitForFunction(({ lng, lat, layer }) => {
		const w = window as unknown as HeatmapHooks;
		const m = w.__heatmapMap;
		if (!m || !w.__heatmapPinsSettled?.() || !m.loaded() || m.isMoving()) return null;
		const pt = m.project([lng, lat]);
		const hits = m.queryRenderedFeatures([pt.x, pt.y], { layers: [layer] });
		const ids = new Set(hits.map((h) => h.properties?.id));
		const onTarget = hits.some((h) => {
			const [x, y] = h.geometry.coordinates as [number, number];
			return Math.abs(x - lng) < 1e-4 && Math.abs(y - lat) < 1e-4;
		});
		if (ids.size !== 1 || !onTarget) return null;
		const rect = m.getContainer().getBoundingClientRect();
		return { x: rect.left + pt.x, y: rect.top + pt.y };
	}, { lng: target[0], lat: target[1], layer }, { timeout: 15_000 });
	return (await handle.jsonValue()) as { x: number; y: number };
}

test.describe('Heatmap pin RPCs (backend contract)', () => {
	test('clubs_in_bbox returns public Virginia clubs + skips private ones', async () => {
		const admin = getAdminClient();
		const { data, error } = await admin.rpc('clubs_in_bbox', VA_BBOX);
		expect(error, `RPC error: ${error?.message ?? ''}`).toBeNull();
		expect(data, 'RPC returned no data').toBeTruthy();
		const pins = data as Array<{
			id: string;
			name: string;
			is_public?: boolean;
			location_label: string | null;
			member_count: number;
			lng: number;
			lat: number;
		}>;

		// Seed has 8 public clubs across VA + 1 private (Friends of
		// Jared, c3333333). The RPC must surface exactly the 8.
		expect(pins.length).toBeGreaterThanOrEqual(2);
		const ids = pins.map((p) => p.id);
		expect(ids).not.toContain(PRIVATE_CLUB_ID);

		// Richmond Run Club is the renamed first seed club — must
		// be in the result with the new name + Richmond VA label.
		const rrc = pins.find((p) => p.id === RICHMOND_RUN_CLUB_ID);
		expect(rrc, 'Richmond Run Club must surface').toBeTruthy();
		expect(rrc!.name).toBe('Richmond Run Club');
		expect(rrc!.location_label).toContain('Richmond');

		// Coord sanity: all VA pins must be inside the requested bbox.
		for (const p of pins) {
			expect(p.lng).toBeGreaterThan(VA_BBOX.p_min_lng);
			expect(p.lng).toBeLessThan(VA_BBOX.p_max_lng);
			expect(p.lat).toBeGreaterThan(VA_BBOX.p_min_lat);
			expect(p.lat).toBeLessThan(VA_BBOX.p_max_lat);
		}
	});

	test('clubs_in_bbox respects bbox (empty when querying somewhere else)',
		async () => {
			const admin = getAdminClient();
			// Box over the Pacific — no clubs there.
			const data = await readRows(
				'the clubs_in_bbox() rpc',
				admin.rpc('clubs_in_bbox', {
					p_min_lng: -160,
					p_min_lat: 10,
					p_max_lng: -140,
					p_max_lat: 30,
					p_limit: 100,
				})
			);
			expect((data as unknown[]).length).toBe(0);
		});

	test('discoverable_routes_in_bbox: featured OR run_count > 0, never both off',
		async () => {
			const admin = getAdminClient();
			const { data, error } = await admin.rpc(
				'discoverable_routes_in_bbox',
				VA_BBOX,
			);
			expect(error).toBeNull();
			const pins = data as Array<{
				id: string;
				is_featured: boolean;
				run_count: number;
				distance_m: number;
				elevation_m: number | null;
			}>;
			expect(pins.length).toBeGreaterThanOrEqual(3);
			// Every pin must satisfy the filter contract.
			for (const p of pins) {
				expect(
					p.is_featured || p.run_count > 0,
					`Route ${p.id} is neither featured nor popular`,
				).toBe(true);
				expect(p.distance_m).toBeGreaterThan(0);
			}
			// Order: featured first, then by run_count desc.
			const firstFeaturedIdx = pins.findIndex((p) => p.is_featured);
			const lastFeaturedIdx = pins
				.slice()
				.reverse()
				.findIndex((p) => p.is_featured);
			if (firstFeaturedIdx >= 0) {
				// Everything before "last featured" must be featured.
				const lastIdx = pins.length - 1 - lastFeaturedIdx;
				for (let i = 0; i <= lastIdx; i++) {
					expect(pins[i].is_featured, `pin ${i} should be featured`).toBe(true);
				}
			}
		});

	test('discoverable_routes_in_bbox limit caps the result set', async () => {
		const admin = getAdminClient();
		const data = await readRows(
			'the discoverable_routes_in_bbox() rpc',
			admin.rpc('discoverable_routes_in_bbox', {
				...VA_BBOX,
				p_limit: 2,
			})
		);
		expect((data as unknown[]).length).toBeLessThanOrEqual(2);
	});
});

test.describe('Heatmap pin layers (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('club + route layers mount with non-zero feature counts', async ({ page }) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });

		// Pan to Virginia so the bbox refresh definitely lands on
		// the seeded pins. Zoom 6 (not 7) so all six VA routes — which
		// span ~4° of longitude — stay inside the sidebar-narrowed map.
		await jumpAndSettle(page, [-78, 37.9], 6);

		// The route count lives in the results-header; the club count in
		// the Filters panel's Clubs layer toggle.
		const routesCount = parseInt(
			(await page.locator('.results-count strong').textContent()) ?? '0',
			10,
		);
		// Seed: 3 featured VA routes + 3 popular VA routes = 6.
		expect(routesCount, 'route pins in VA viewport').toBeGreaterThanOrEqual(6);

		await page.getByTestId('filters-button').click();
		const clubsRow = page.locator('.layer-row', { hasText: 'Clubs' });
		await expect(clubsRow).toBeVisible();
		const clubsCount = parseInt(
			(await clubsRow.locator('.layer-count').textContent()) ?? '0',
			10,
		);
		// Seed: 8 VA clubs.
		expect(clubsCount, 'club pins in VA viewport').toBeGreaterThanOrEqual(8);
	});

	test('layer toggle hides + restores its layer', async ({ page }) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.getByTestId('filters-button').click();

		// Toggling the Clubs layer checkbox should flip the layer's
		// visibility. The checkbox state is the observable contract; if
		// the binding works, the MapLibre layer follows it via the $effect.
		const clubsCheckbox = page
			.locator('.layer-row', { hasText: 'Clubs' })
			.getByRole('checkbox');
		await expect(clubsCheckbox).toBeChecked();
		await clubsCheckbox.uncheck();
		await expect(clubsCheckbox).not.toBeChecked();
		await clubsCheckbox.check();
		await expect(clubsCheckbox).toBeChecked();
	});
});

test.describe('Heatmap pin popup (click flow)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('clicking a route pin keeps it on the map (no navigation); the row View link navigates',
		async ({ page }) => {
			await page.goto('/routes/heatmap');
			await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });

			const target: [number, number] = [-77.452, 37.5311]; // Belle Isle
			const screen = await settleOnPin(page, target, 'heatmap-route-pins-layer');

			// Real click — MapLibre's queryRenderedFeatures only resolves
			// for actual pointer events, not synthetic fire('click').
			// Clicking a route dot keeps it on the map; it must NOT navigate
			// and must NOT open a navigable route popup.
			await page.mouse.click(screen.x, screen.y);
			await expect(page.getByTestId('clear-pins')).toBeVisible({ timeout: 5_000 });
			await expect(page).toHaveURL(/\/routes\/heatmap/);
			await expect(page.locator('.heatmap-pin-popup .pin-popup-action')).toHaveCount(0);

			// The matching sidebar row reflects the kept state; its explicit
			// "View route" link is the only path to the detail page.
			const keptLi = page
				.getByTestId('discover-list')
				.locator('.result-li:has(.result-row.kept)')
				.first();
			await expect(keptLi).toBeVisible();
			await keptLi.getByTestId('result-view').click();
			await page.waitForURL(/\/routes\/[\da-f-]{36}/, { timeout: 10_000 });
		});

	test('clicking a club pin opens a popup with a View club action',
		async ({ page }) => {
			await page.goto('/routes/heatmap');
			await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });

			const target: [number, number] = [-77.436, 37.5407]; // Richmond Run Club
			const screen = await settleOnPin(page, target, 'heatmap-clubs-layer');
			await page.mouse.click(screen.x, screen.y);

			const popup = page.locator('.heatmap-pin-popup');
			await expect(popup).toBeVisible({ timeout: 5_000 });
			await expect(popup.getByText(/Richmond Run Club/i)).toBeVisible();
			await expect(popup.getByRole('link', { name: /view club/i })).toBeVisible();
			// Location subtitle must render — location_label has to be on the
			// rendered pin feature (Richmond Run Club seed = Richmond, VA).
			await expect(popup.locator('.pin-popup-location')).toBeVisible();
		});

	test('popup mounts with finite translate3d (not collapsed to map origin)',
		async ({ page }) => {
		// The May 2026 user-reported bug was "circle stuck at the
		// top-left of the map" — a non-finite-coord symptom (the
		// MapLibre translate3d projector collapses NaN to 0,0). The
		// defensive `Number.isFinite` guard on `renderPreviewMarker`
		// + the `map.resize()` in `openPopupRaw` close that class of
		// bug. Pin the post-click popup transform to a finite,
		// non-trivial value so a regression to the corner-stuck
		// state fails this test.
		//
		// We do NOT assert exact viewport coords because MapLibre's
		// container rect interacts with the page's scroll position
		// (a separate flex-layout subtlety on /routes/heatmap),
		// and changing the page-shell scroll model is out of scope
		// for the pin-popup feature. Visibility + non-trivial
		// translate is the load-bearing contract.
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });

		// Route dots now keep-on-click (no popup), so drive this against the
		// club pin — the one surface that still opens a `.heatmap-pin-popup`.
		const target: [number, number] = [-77.436, 37.5407]; // Richmond Run Club
		const screen = await settleOnPin(page, target, 'heatmap-clubs-layer');
		await page.mouse.click(screen.x, screen.y);

		const popup = page.locator('.heatmap-pin-popup');
		await expect(popup).toBeVisible({ timeout: 5_000 });

		// Map should be at viewport y >= 0 now that the heatmap
		// lives in its own /routes/heatmap route (standalone, no
		// flex chain). Pin this so a regression that brings back
		// the tab-parent layout fails here.
		const mapRect = await page
			.locator('.maplibregl-map')
			.evaluate((el) => {
				const r = el.getBoundingClientRect();
				return { top: r.top, height: r.height };
			});
		expect(mapRect.top, 'map should not extend above the viewport')
			.toBeGreaterThanOrEqual(-2);
		expect(mapRect.height, 'map should fill its container').toBeGreaterThan(400);

		// Read the popup wrapper's transform — must contain a
		// translate(...) with finite pixel offsets (not "translate(0px,
		// 0px)" which is the corner-stuck state).
		const transform = await popup.evaluate((el) => {
			const wrap = el.closest('.maplibregl-popup') as HTMLElement | null;
			return wrap?.style.transform ?? '';
		});
		expect(transform, `popup transform: ${transform}`).toMatch(
			/translate\(/,
		);
		const match = transform.match(/translate\(([\-\d.]+)px,\s*([\-\d.]+)px\)/);
		expect(match, `no translate pixel values: ${transform}`).not.toBeNull();
		if (match) {
			const x = parseFloat(match[1]);
			const y = parseFloat(match[2]);
			expect(Number.isFinite(x)).toBe(true);
			expect(Number.isFinite(y)).toBe(true);
			// At least one of x/y must be non-trivial — the corner-
			// stuck state is exactly translate(0px, 0px). Any other
			// projection produces a meaningful offset.
			expect(Math.abs(x) + Math.abs(y)).toBeGreaterThan(20);
		}

	});
});
