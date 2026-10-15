import { expect, test } from '../fixtures/test';

import { getAdminClient, resetRateLimit } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * "Your Strava clubs" (issue #1151 step 4, decisions § 1959) on a build with no
 * `PUBLIC_STRAVA_CLIENT_ID` — every CI lane, and local dev by default.
 *
 * The section and the create page's link step sit behind `isStravaConfigured()`
 * so they stay inert wherever Strava is not set up. What is pinned here is that
 * inertness, against a runner who IS connected (USER_A's seed carries a Strava
 * integration row) and with `strava-clubs` answering as if it would happily
 * list clubs: a gate that read the integration row instead of the build would
 * render the section and spend a call. The section's own behaviour on a
 * configured build is pinned by the function's Deno tests and the pure
 * `strava_clubs.test.ts`; no lane builds with a Strava client id (followups).
 *
 * If a lane ever does build with one, the first test fails by design — it is
 * then the wrong lane for it, not a broken gate.
 */

const LISTED = {
	status: 'connected',
	clubs: [
		{
			strava_club_id: 101,
			name: 'Strava Only Striders',
			city: 'Leeds',
			state: null,
			country: 'United Kingdom',
			sport_type: 'running',
			member_count: 12,
			profile_url: null,
			viewer_is_admin: true,
			linked_club: null,
		},
	],
};

test.describe('Your Strava clubs — unconfigured build', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('My clubs never asks Strava, even for a connected runner', async ({ page, mockRoute }) => {
		await mockRoute(
			page,
			'**/functions/v1/strava-clubs',
			(route) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(LISTED) }),
			{ neverFires: 'an unconfigured build must not ask Strava for clubs' },
		);

		await page.goto('/social?tab=clubs');
		// The runner's own club rendering is the proof the tab settled rather
		// than the assertions below reading a page that had not loaded.
		await expect(page.locator('.card', { hasText: 'Richmond Run Club' }).first()).toBeVisible({
			timeout: 15_000,
		});
		await page.waitForLoadState('networkidle');

		await expect(page.getByTestId('strava-clubs')).toHaveCount(0);
		await expect(page.getByText('Strava Only Striders')).toHaveCount(0);
	});

	test('setting up a Strava club fills the form, and the new club is created unlinked', async ({
		page,
		mockRoute,
	}) => {
		await mockRoute(
			page,
			'**/functions/v1/strava-clubs',
			(route) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true }) }),
			{ neverFires: 'an unconfigured build must not try to link the new club to Strava' },
		);
		await page.route('**/api.maptiler.com/geocoding/**', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ type: 'FeatureCollection', features: [] }),
			}),
		);
		await resetRateLimit(USER_A.id, 'create_club');

		const name = `Strava Only Striders ${Date.now()}`;
		const params = new URLSearchParams({ name, location: 'Leeds, United Kingdom', strava_club: '101' });
		await page.goto(`/clubs/new?${params.toString()}`);

		await expect(page.getByRole('textbox', { name: 'Name', exact: true })).toHaveValue(name, { timeout: 15_000 });
		await expect(page.getByRole('textbox', { name: /^Location/ })).toHaveValue('Leeds, United Kingdom');
		await expect(page.getByTestId('clubs-new-strava-note')).toHaveCount(0);

		await page.getByRole('button', { name: 'Create club' }).click();
		await page.waitForURL(/\/clubs\/[a-z0-9-]*\d[a-z0-9-]*$/, { timeout: 15_000 });
		const slug = page.url().match(/\/clubs\/([a-z0-9-]+)$/)![1];

		const admin = getAdminClient();
		const { data, error } = await admin
			.from('clubs')
			.select('id, location_label, strava_club_id')
			.eq('slug', slug)
			.single();
		try {
			if (error || !data) throw new Error(`created club ${slug} not found: ${error?.message}`);
			expect(data.location_label).toBe('Leeds, United Kingdom');
			expect(data.strava_club_id).toBeNull();
		} finally {
			if (data) await admin.from('clubs').delete().eq('id', data.id);
			await resetRateLimit(USER_A.id, 'create_club');
		}
	});
});
