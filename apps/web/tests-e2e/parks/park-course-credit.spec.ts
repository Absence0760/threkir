import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * A park course's source credit lives in `park_courses.attribution`, not in
 * its segment's or route's description (issue #1352, decisions § 2438), so
 * the two pages that show a park course outside its own page read the
 * column: the catalogue segment page and the official route page each show
 * the credit once, and an ordinary route shows none.
 *
 * Fixtures sit at (51, 11), which no seed row or other spec touches, inside a
 * club this spec verifies with the service role.
 */

const CLUB_ID = crypto.randomUUID();
const ROUTE_ID = crypto.randomUUID();
const PLAIN_ROUTE_ID = crypto.randomUUID();
const TAG = CLUB_ID.slice(0, 8);
const CREDIT = `© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP ${TAG}`;
const ROUTE_NAME = `Credit course route ${TAG}`;
const PLAIN_ROUTE_NAME = `Credit plain route ${TAG}`;
let parkId: string | null = null;
let segmentId: string | null = null;

test.describe('park course credit (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const club = await admin.from('clubs').insert({
			id: CLUB_ID,
			owner_id: USER_B.id,
			name: `Credit org ${TAG}`,
			slug: `credit-org-${TAG}`,
			is_public: true,
		});
		if (club.error) throw club.error;
		const verified = await admin.from('clubs').update({ is_verified: true }).eq('id', CLUB_ID);
		if (verified.error) throw verified.error;
		const waypoints = [
			{ lat: 51.0, lng: 11.0 },
			{ lat: 51.009, lng: 11.0 },
		];
		const routes = await admin.from('routes').insert([
			{
				id: ROUTE_ID,
				user_id: USER_B.id,
				club_id: CLUB_ID,
				name: ROUTE_NAME,
				description: 'Run it clockwise.',
				distance_m: 1000,
				is_public: true,
				surface: 'trail',
				waypoints,
			},
			{
				id: PLAIN_ROUTE_ID,
				user_id: USER_B.id,
				name: PLAIN_ROUTE_NAME,
				description: 'Run it clockwise.',
				distance_m: 1000,
				is_public: true,
				surface: 'trail',
				waypoints,
			},
		]);
		if (routes.error) throw routes.error;
		const seg = await admin
			.from('global_segments')
			.insert({
				name: `Credit segment ${TAG}`,
				description: 'Run it clockwise.',
				waypoints,
				distance_m: 1000,
				surface: 'trail',
				country_code: 'US',
			})
			.select('id')
			.single();
		if (seg.error) throw seg.error;
		segmentId = seg.data.id;
		const park = await admin
			.from('parks')
			.insert({
				slug: `e2e-credit-park-${TAG}`,
				name: `E2E Credit Park ${TAG}`,
				agency: 'state',
				region_code: 'US-VA',
				country_code: 'US',
				timezone: 'America/New_York',
			})
			.select('id')
			.single();
		if (park.error) throw park.error;
		parkId = park.data.id;
		const course = await admin.from('park_courses').insert({
			park_id: parkId,
			global_segment_id: segmentId,
			route_id: ROUTE_ID,
			slug: 'credit-loop',
			course_shape: 'point_to_point',
			geometry_source: 'osm',
			checkpoints: [],
			laps: null,
			attribution: CREDIT,
		});
		if (course.error) throw course.error;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (parkId) await admin.from('parks').delete().eq('id', parkId);
		if (segmentId) await admin.from('global_segments').delete().eq('id', segmentId);
		await admin.from('routes').delete().in('id', [ROUTE_ID, PLAIN_ROUTE_ID]);
		await admin.from('clubs').delete().eq('id', CLUB_ID);
	});

	test('the segment page shows the course credit once, under the description', async ({ page }) => {
		await page.goto(`/segments/${segmentId}`);
		await expect(page.getByText('Run it clockwise.')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('segment-course-credit')).toHaveText(CREDIT);
		await expect(page.getByText(CREDIT)).toHaveCount(1);
	});

	test('the official route page shows the course credit; an ordinary route shows none', async ({ page }) => {
		await page.goto(`/routes/${ROUTE_ID}`);
		await expect(page.getByRole('heading', { level: 1, name: ROUTE_NAME })).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('route-course-credit')).toHaveText(CREDIT);
		await expect(page.getByText(CREDIT)).toHaveCount(1);

		await page.goto(`/routes/${PLAIN_ROUTE_ID}`);
		await expect(page.getByRole('heading', { level: 1, name: PLAIN_ROUTE_NAME })).toBeVisible({
			timeout: 15_000,
		});
		await expect(page.getByText('Run it clockwise.')).toBeVisible();
		await expect(page.getByTestId('route-course-credit')).toHaveCount(0);
	});
});
