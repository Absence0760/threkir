import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';
import { jumpAndSettle } from '../fixtures/heatmap';

/**
 * Official content (issue #1190, migration 20271021000030 + 031): a route
 * published by a verified club's owner reads as official. The heatmap's
 * Official lens lists it with the badge, and the route page carries the
 * badge; a public route by the same person outside the club does not.
 *
 * The fixtures live at (10, 50), a spot no seed route or other spec's
 * fixture touches, inside a club this spec creates and verifies with the
 * service-role client (the only writer `clubs.is_verified` accepts).
 */

const CLUB_ID = crypto.randomUUID();
const OFFICIAL_ID = crypto.randomUUID();
const PERSONAL_ID = crypto.randomUUID();
const OFFICIAL_NAME = `Official course ${CLUB_ID.slice(0, 8)}`;
const PERSONAL_NAME = `Personal loop ${CLUB_ID.slice(0, 8)}`;

test.describe('official content (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const club = await admin.from('clubs').insert({
			id: CLUB_ID,
			owner_id: USER_B.id,
			name: `Official org ${CLUB_ID.slice(0, 8)}`,
			slug: `official-org-${CLUB_ID.slice(0, 8)}`,
			is_public: true,
		});
		if (club.error) throw club.error;
		const verified = await admin.from('clubs').update({ is_verified: true }).eq('id', CLUB_ID);
		if (verified.error) throw verified.error;
		const routes = await admin.from('routes').insert([
			{
				id: OFFICIAL_ID,
				user_id: USER_B.id,
				club_id: CLUB_ID,
				name: OFFICIAL_NAME,
				distance_m: 10000,
				is_public: true,
				is_featured: false,
				surface: 'road',
				waypoints: [
					{ lng: 10.0, lat: 50.0 },
					{ lng: 10.01, lat: 50.01 },
				],
			},
			{
				id: PERSONAL_ID,
				user_id: USER_B.id,
				name: PERSONAL_NAME,
				distance_m: 8000,
				is_public: true,
				is_featured: true,
				surface: 'road',
				waypoints: [
					{ lng: 10.02, lat: 50.02 },
					{ lng: 10.03, lat: 50.03 },
				],
			},
		]);
		if (routes.error) throw routes.error;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		await admin.from('routes').delete().in('id', [OFFICIAL_ID, PERSONAL_ID]);
		await admin.from('clubs').delete().eq('id', CLUB_ID);
	});

	test('the Official lens lists the verified club route with its badge', async ({ page }) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await jumpAndSettle(page, [10.015, 50.015], 12);

		const list = page.getByTestId('discover-list');
		const officialRow = list.locator('.result-li', { hasText: OFFICIAL_NAME });
		const personalRow = list.locator('.result-li', { hasText: PERSONAL_NAME });

		// The default lens pins the un-run official route, ranked first.
		await expect(officialRow).toBeVisible({ timeout: 10_000 });
		await expect(officialRow.getByTestId('official-badge')).toBeVisible();
		await expect(personalRow).toBeVisible();
		await expect(personalRow.getByTestId('official-badge')).toHaveCount(0);
		await expect(list.locator('.result-li').first()).toContainText(OFFICIAL_NAME);

		await page.getByTestId('filters-button').click();
		const officialChip = page.getByTestId('filters-panel').locator('[data-filter="official"]');
		await officialChip.click();
		await expect(officialChip).toHaveAttribute('aria-pressed', 'true');
		await expect(personalRow).toHaveCount(0, { timeout: 10_000 });
		await expect(officialRow).toBeVisible();
	});

	test('the route page carries the badge only on official content', async ({ page }) => {
		await page.goto(`/routes/${OFFICIAL_ID}`);
		await expect(page.getByRole('heading', { level: 1, name: OFFICIAL_NAME })).toBeVisible({
			timeout: 15_000,
		});
		const badge = page.locator('.detail-header').getByTestId('official-badge');
		await expect(badge).toBeVisible();
		await expect(badge).toHaveAttribute('title', 'Official: published by a verified organiser');

		await page.goto(`/routes/${PERSONAL_ID}`);
		await expect(page.getByRole('heading', { level: 1, name: PERSONAL_NAME })).toBeVisible({
			timeout: 15_000,
		});
		await expect(page.locator('.detail-header').getByTestId('official-badge')).toHaveCount(0);
	});
});
