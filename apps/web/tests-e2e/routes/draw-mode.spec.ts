import { expect, test } from '../fixtures/test';
import type { Page } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Draw mode (route art, decisions § 2263). The stroke is handed to the
 * builder through its `drawShape` export on the DEV-only `__routeBuilder`
 * hook, since MapLibre's WebGL pointer pipeline does not deliver synthetic
 * drags reliably in headless chromium. OSRM rides the /api/routes/osrm proxy,
 * so that is the intercept.
 */

type Pt = { lat: number; lng: number };

/// A ~1 km square around the map centre, drawn as a closed loop.
async function squareAroundCentre(page: Page): Promise<Pt[]> {
	const centre = await page.evaluate(() =>
		(
			window as unknown as { __routeBuilder: { getMapCenter: () => Pt | null } }
		).__routeBuilder.getMapCenter(),
	);
	if (!centre) throw new Error('Map centre not available');
	const h = 0.0045;
	const w = h / Math.cos((centre.lat * Math.PI) / 180);
	const corners: Pt[] = [
		{ lat: centre.lat - h, lng: centre.lng - w },
		{ lat: centre.lat - h, lng: centre.lng + w },
		{ lat: centre.lat + h, lng: centre.lng + w },
		{ lat: centre.lat + h, lng: centre.lng - w },
		{ lat: centre.lat - h, lng: centre.lng - w },
	];
	const out: Pt[] = [];
	for (let c = 0; c < corners.length - 1; c++) {
		for (let i = 0; i < 20; i++) {
			const f = i / 20;
			out.push({
				lat: corners[c].lat + (corners[c + 1].lat - corners[c].lat) * f,
				lng: corners[c].lng + (corners[c + 1].lng - corners[c].lng) * f,
			});
		}
	}
	return out;
}

async function openBuilder(page: Page): Promise<void> {
	await page.route('https://api.open-meteo.com/**', (route) =>
		route.fulfill({
			status: 200,
			contentType: 'application/json',
			body: JSON.stringify({ elevation: Array(100).fill(10) }),
		}),
	);
	await page.goto('/routes/new');
	await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
	await page.waitForFunction(
		() => typeof (window as unknown as { __routeBuilder?: unknown }).__routeBuilder !== 'undefined',
		undefined,
		{ timeout: 10_000 },
	);
}

async function draw(page: Page, pts: Pt[]): Promise<void> {
	await page.evaluate(
		(points) =>
			(
				window as unknown as { __routeBuilder: { drawShape: (p: Pt[]) => Promise<void> } }
			).__routeBuilder.drawShape(points),
		pts,
	);
}

function routeCoords(url: string): [number, number][] {
	const m = url.match(/\/route\/v1\/foot\/([^?]+)/);
	return m ? m[1].split(';').map((p) => p.split(',').map(Number) as [number, number]) : [];
}

test.describe('/routes/new — Draw mode', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the toggle is a pressed-state button and swaps the empty state for the draw hint', async ({
		page,
	}) => {
		await openBuilder(page);
		const toggle = page.getByTestId('draw-mode-toggle');
		await expect(toggle).toHaveAttribute('aria-pressed', 'false');
		await toggle.click();
		await expect(toggle).toHaveAttribute('aria-pressed', 'true');
		await expect(page.getByTestId('draw-hint')).toBeVisible();
		await expect(page.locator('.canvas-empty')).toHaveCount(0);
	});

	test('a drawing the roads can follow becomes the route, with its score', async ({ page, mockRoute }) => {
		const calls: [number, number][][] = [];
		await mockRoute(page, '**/api/routes/osrm/**', (route) => {
			const coords = routeCoords(route.request().url());
			calls.push(coords);
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ code: 'Ok', routes: [{ geometry: { coordinates: coords }, distance: 1000 }] }),
			});
		});
		await openBuilder(page);
		await page.getByTestId('draw-mode-toggle').click();
		await draw(page, await squareAroundCentre(page));

		const match = page.getByTestId('art-match');
		await expect(match).toBeVisible({ timeout: 15_000 });
		await expect(match).toContainText('100%');
		await expect(match).toContainText('Close match');
		await expect(page.getByRole('button', { name: /Save Route/ })).toBeEnabled();
		// One call per 60 points, each within the proxy's ceiling.
		expect(calls.length).toBeGreaterThan(0);
		for (const c of calls) expect(c.length).toBeLessThanOrEqual(60);
	});

	test('a drawing the roads cannot follow says so and is not saveable', async ({ page, mockRoute }) => {
		await mockRoute(page, '**/api/routes/osrm/**', (route) => {
			const coords = routeCoords(route.request().url());
			// The engine answers with a straight line between the first and
			// last point — a different picture from the square that was drawn.
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					code: 'Ok',
					routes: [{ geometry: { coordinates: [coords[0], coords[coords.length - 1]] }, distance: 10 }],
				}),
			});
		});
		await openBuilder(page);
		await page.getByTestId('draw-mode-toggle').click();
		await draw(page, await squareAroundCentre(page));

		const match = page.getByTestId('art-match');
		await expect(match).toBeVisible({ timeout: 15_000 });
		await expect(match).toContainText('Too far from your drawing');
		await expect(page.locator('.routing-error')).toContainText('match only');
		await expect(page.getByRole('button', { name: /Save Route/ })).toBeDisabled();
	});

	test('a drawing with no road nearby names the problem', async ({ page }) => {
		await page.route('**/api/routes/osrm/**', (route) =>
			route.fulfill({
				status: 422,
				contentType: 'application/json',
				body: JSON.stringify({ error: 'no_route_for_coordinates' }),
			}),
		);
		await openBuilder(page);
		await page.getByTestId('draw-mode-toggle').click();
		await draw(page, await squareAroundCentre(page));
		await expect(page.locator('.routing-error')).toContainText('no road or path nearby', { timeout: 15_000 });
		await expect(page.getByRole('button', { name: /Save Route/ })).toBeDisabled();
	});
});
