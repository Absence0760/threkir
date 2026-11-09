import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';
import { jumpAndSettle, settleOnFeature } from '../fixtures/heatmap';

/**
 * Upcoming verified races on the discovery map (issue #1190 § 4,
 * `upcoming_races_in_bbox`, migration 20271125002408).
 *
 *   1. The pin layer is on by default and counts the verified race; an
 *      unverified fan copy beside it never pins.
 *   2. Clicking the pin opens a popup whose View race link opens /races/<id>.
 *   3. The Races toggle hides the layer.
 *   4. The Official lens narrows the races to official organisers', so a
 *      provider-verified race drops out.
 *
 * The fixtures sit in central Finland, clear of every seeded route, club and
 * race.
 */

const TARGET: [number, number] = [25.0, 62.0];
const VERIFIED_ID = crypto.randomUUID();
const FAN_ID = crypto.randomUUID();

function isoDaysFromNow(days: number): string {
	return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
}

test.describe.serial('Heatmap upcoming race pins (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { error } = await admin.from('race_listings').insert([
			{
				id: VERIFIED_ID,
				provider: 'runsignup',
				provider_race_id: `e2e-race-pin-${VERIFIED_ID}`,
				name: 'Lakeland Pin Half',
				race_date: isoDaysFromNow(40),
				distance_m: 21097,
				location_label: 'Lakeland',
				location_point: `SRID=4326;POINT(${TARGET[0]} ${TARGET[1]})`,
				is_verified: true,
			},
			{
				id: FAN_ID,
				provider: 'manual',
				name: 'Lakeland Pin Half (fan copy)',
				race_date: isoDaysFromNow(40),
				distance_m: 21097,
				location_label: 'Lakeland',
				location_point: `SRID=4326;POINT(${TARGET[0] + 0.05} ${TARGET[1]})`,
				is_verified: false,
			},
		]);
		expect(error, `fixture insert: ${error?.message ?? ''}`).toBeNull();
	});

	test.afterAll(async () => {
		await getAdminClient().from('race_listings').delete().in('id', [VERIFIED_ID, FAN_ID]);
	});

	test('the verified race pins and counts; the fan copy does not', async ({ page }) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await settleOnFeature(page, TARGET, 11, 'heatmap-race-pins-layer', { single: true });

		const ids = await page.evaluate(() => {
			const m = (window as unknown as { __heatmapMap?: any }).__heatmapMap;
			return (m?.querySourceFeatures('heatmap-race-pins') ?? []).map(
				(f: { properties?: { id?: string } }) => f.properties?.id,
			);
		});
		expect(ids).toContain(VERIFIED_ID);
		expect(ids).not.toContain(FAN_ID);

		await page.getByTestId('filters-button').click();
		await expect(page.getByTestId('race-pins-toggle')).toBeChecked();
		await expect(page.getByTestId('race-pins-count')).toHaveText('1');
	});

	test('clicking the race pin opens a popup that links to the race', async ({ page }) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		const screen = await settleOnFeature(page, TARGET, 11, 'heatmap-race-pins-layer', {
			single: true,
		});
		await page.mouse.click(screen.x, screen.y);

		const popup = page.locator('.heatmap-pin-popup');
		await expect(popup).toBeVisible({ timeout: 5_000 });
		await expect(popup.getByText('Lakeland Pin Half', { exact: true })).toBeVisible();
		await expect(popup.locator('.pin-popup-location')).toHaveText('Lakeland');
		const link = popup.getByRole('link', { name: /view race/i });
		await expect(link).toHaveAttribute('href', `/races/${VERIFIED_ID}`);
		await link.click();
		await page.waitForURL(new RegExp(`/races/${VERIFIED_ID}$`), { timeout: 10_000 });
	});

	test('the Races toggle hides the layer; the Official lens drops a non-official race', async ({
		page,
	}) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await jumpAndSettle(page, TARGET, 11);

		const visibility = () =>
			page.evaluate(() => {
				const m = (window as unknown as { __heatmapMap?: any }).__heatmapMap;
				return m?.getLayoutProperty('heatmap-race-pins-layer', 'visibility') ?? 'visible';
			});
		await page.getByTestId('filters-button').click();
		const toggle = page.getByTestId('race-pins-toggle');
		await expect(page.getByTestId('race-pins-count')).toHaveText('1');
		await toggle.uncheck();
		await expect.poll(visibility).toBe('none');
		await toggle.check();
		await expect.poll(visibility).toBe('visible');

		await page.getByTestId('filters-panel').locator('[data-filter="official"]').click();
		await expect(page.getByTestId('race-pins-count')).toHaveText('0');
	});
});
