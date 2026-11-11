import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * The park course pages as the owner reviewed them (issue #1352): a park's
 * courses sorted by distance with readable distances and a laps chip, the
 * index card's course count and distance range, the course page's map key,
 * its one credit line, its one primary action, an empty board that invites a
 * first run with its filters hidden, and the notices callout: the times
 * notice on every course and the give-way note on a course an organised group
 * shares (decisions § 2459).
 *
 * Every row is planted (service role) in one park under a unique slug, at
 * (37.4, -78.4), which no seed row or other spec uses, and removed afterwards.
 */

const M_PER_DEG_LAT = 111_320;
const BASE_LAT = 37.4;
const LNG = -78.4;
const TAG = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
const PARK_SLUG = `e2e-pages-park-${TAG}`;
const PARK_NAME = `E2E Pages State Park ${TAG}`;
const CREDIT = `© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP ${TAG}`;

// Alphabetical order would be Beaver, 10 km, 50 km, 5 km, Half: the page must
// not list them that way.
const COURSES = [
	{ slug: 'beaver-lake', name: `Beaver Lake Trail ${TAG}`, distanceM: 7_400, laps: 1, shape: 'loop' },
	{ slug: '10k', name: `10 km ${TAG}`, distanceM: 10_000, laps: 2, shape: 'loop' },
	{ slug: '50k', name: `50 km ${TAG}`, distanceM: 50_000, laps: null, shape: 'point_to_point' },
	{ slug: '5k', name: `5 km ${TAG}`, distanceM: 5_000, laps: 1, shape: 'loop' },
	{ slug: 'half', name: `Half marathon ${TAG}`, distanceM: 21_100, laps: null, shape: 'out_and_back' },
] as const;

let parkId: string | null = null;
const segmentIds: string[] = [];

test.beforeAll(async () => {
	const admin = getAdminClient();
	const park = await admin
		.from('parks')
		.insert({
			slug: PARK_SLUG,
			name: PARK_NAME,
			agency: 'state',
			region_code: 'US-VA',
			country_code: 'US',
			timezone: 'America/New_York',
			website_url: 'https://example.gov/e2e-pages-park',
		})
		.select('id')
		.single();
	if (park.error) throw park.error;
	parkId = park.data.id;
	for (const [i, c] of COURSES.entries()) {
		const lng = LNG + i * 0.01;
		const seg = await admin
			.from('global_segments')
			.insert({
				name: c.name,
				description: 'Run it clockwise.',
				waypoints: [
					{ lat: BASE_LAT, lng },
					{ lat: BASE_LAT + 1000 / M_PER_DEG_LAT, lng },
				],
				distance_m: c.distanceM,
				surface: 'trail',
				country_code: 'US',
			})
			.select('id')
			.single();
		if (seg.error) throw seg.error;
		segmentIds.push(seg.data.id);
		const course = await admin.from('park_courses').insert({
			park_id: parkId,
			global_segment_id: seg.data.id,
			slug: c.slug,
			course_shape: c.shape,
			geometry_source: 'osm',
			checkpoints: [{ lat: BASE_LAT + 500 / M_PER_DEG_LAT, lng }],
			laps: c.laps,
			attribution: c.slug === '5k' ? CREDIT : null,
			shared_use: c.slug === '5k' ? 'saturday_morning_group' : null,
		});
		if (course.error) throw course.error;
	}
});

test.afterAll(async () => {
	const admin = getAdminClient();
	if (parkId) await admin.from('parks').delete().eq('id', parkId);
	if (segmentIds.length) await admin.from('global_segments').delete().in('id', segmentIds);
});

test.describe('park course pages', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the index card carries the course count and distance range', async ({ page }) => {
		await page.goto('/parks');
		const card = page.getByTestId('park-card').filter({ hasText: PARK_NAME });
		await expect(card).toBeVisible({ timeout: 15_000 });
		await expect(card.getByTestId('park-card-facts')).toHaveText('5 courses · 5–50 km');
	});

	test('the park lists its courses by distance, with readable distances and a laps chip', async ({ page }) => {
		await page.goto(`/parks/us-va/${PARK_SLUG}`);
		await expect(page.getByRole('heading', { level: 1, name: PARK_NAME })).toBeVisible({ timeout: 15_000 });

		// "Park website" sits in its own item of the meta line, apart from the agency.
		const meta = page.getByTestId('park-meta');
		await expect(meta.locator('li')).toHaveCount(3);
		await expect(meta.locator('li').nth(1)).toHaveText('State park');
		await expect(page.getByTestId('park-website')).toHaveAccessibleName('Park website');

		const cards = page.getByTestId('park-course-card');
		await expect(cards).toHaveCount(5);
		await expect(cards.locator('.course-name')).toHaveText([
			COURSES[3].name,
			COURSES[0].name,
			COURSES[1].name,
			COURSES[4].name,
			COURSES[2].name,
		]);
		await expect(cards.getByTestId('park-course-distance')).toHaveText([
			'5 km',
			'7.4 km',
			'10 km',
			'21.1 km',
			'50 km',
		]);
		for (const text of await cards.getByTestId('park-course-distance').allTextContents()) {
			expect(text).not.toMatch(/\d\.\d\d/);
		}

		// Only the 2-lap course carries a chip, and no card says "Loop".
		await expect(cards.getByTestId('park-course-laps')).toHaveCount(1);
		await expect(cards.nth(2).getByTestId('park-course-laps')).toHaveText('2 laps');
		await expect(cards.filter({ hasText: /\bLoop\b/ })).toHaveCount(0);
		await expect(cards.nth(3)).toContainText('Out and back');

		// Signed in with no efforts planted, each course says there is no record yet.
		await expect(cards.first().getByTestId('park-course-record')).toContainText('No time yet this season');
		await expect(page.getByTestId('park-not-affiliated')).toBeVisible();
	});

	test('the course page: map key, one credit line, one primary action, and an inviting empty board', async ({
		page,
	}) => {
		await page.goto(`/parks/us-va/${PARK_SLUG}/5k`);
		await expect(page.getByRole('heading', { level: 1, name: COURSES[3].name })).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('park-course-distance')).toHaveText('5 km');

		// The credit comes from the column, once, and never inside the description.
		await expect(page.getByTestId('park-course-attribution')).toHaveText(CREDIT);
		await expect(page.getByText(CREDIT)).toHaveCount(1);
		await expect(page.getByTestId('park-course-description')).toHaveText('Run it clockwise.');

		const legend = page.getByTestId('park-course-legend');
		await expect(legend).toHaveAttribute('aria-label', 'Map key');
		await expect(legend.locator('li')).toContainText([
			'Start',
			'Finish',
			'Checkpoint: your run must pass it',
			'Kilometre marker',
			'Direction to run',
		]);

		// One callout: the safety notice, the give-way note this shared course
		// carries, the times notice, then the not-affiliated note.
		const notices = page.getByTestId('park-course-notices');
		await expect(notices.locator('li')).toHaveText([
			/^Stay on the marked trail\./,
			'Organised groups use these paths on Saturday mornings. Give way, and avoid timing an effort through them.',
			'Times here are Threkir times on these paths. They are not results of any event held on them.',
			/^Threkir publishes these courses\./,
		]);
		await expect(notices.locator('li').first()).toHaveAttribute('data-testid', 'park-course-safety');
		await expect(notices.getByTestId('park-course-shared-use')).toBeVisible();
		await expect(notices.getByTestId('park-course-times')).toBeVisible();
		await expect(notices.getByTestId('park-course-not-affiliated')).toBeVisible();

		// No route to navigate, so the GPX download is the one primary action.
		await expect(page.getByTestId('park-course-navigate')).toHaveCount(0);
		await expect(page.getByTestId('park-course-gpx')).toHaveClass(/btn-primary/);
		await expect(page.locator('.course-actions .btn-primary')).toHaveCount(1);

		// No times on any board: an invitation, and nothing to switch between.
		await expect(page.getByTestId('park-board-invite')).toContainText('Yours could be the first.');
		await expect(page.getByTestId('park-board-fastest')).toHaveCount(0);
		await expect(page.getByTestId('park-season-all-time')).toHaveCount(0);
		await expect(page.getByTestId('park-board-filters')).toHaveCount(0);
		await expect(page.getByTestId('park-board-compare')).toHaveCount(0);
	});

	test('a course without its own credit falls back to the geometry source label', async ({ page }) => {
		await page.goto(`/parks/us-va/${PARK_SLUG}/half`);
		await expect(page.getByRole('heading', { level: 1, name: COURSES[4].name })).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('park-course-attribution')).toHaveText('Course line © OpenStreetMap contributors');
		await expect(page.getByTestId('park-course-distance')).toHaveText('21.1 km');
		// A course no group shares has the times notice and no give-way note.
		await expect(page.getByTestId('park-course-times')).toBeVisible();
		await expect(page.getByTestId('park-course-shared-use')).toHaveCount(0);
	});
});

test.describe('park course share page', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('reads the distance without decimals and shows one credit line and the notices', async ({ page }) => {
		await page.goto(`/share/course/us-va/${PARK_SLUG}/10k`);
		await expect(page.getByRole('heading', { level: 1, name: COURSES[1].name })).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('share-course-distance')).toHaveText('10 km');
		await expect(page.getByTestId('share-course-laps')).toHaveText('2 laps');
		await expect(page.getByTestId('share-course-attribution')).toHaveCount(1);
		await expect(page.getByTestId('share-course-notices')).toBeVisible();
		await expect(page.getByTestId('share-course-safety')).toBeVisible();
		await expect(page.getByTestId('share-course-times')).toBeVisible();
		await expect(page.getByTestId('share-course-shared-use')).toHaveCount(0);
	});

	test('carries the give-way note on a course an organised group shares', async ({ page }) => {
		await page.goto(`/share/course/us-va/${PARK_SLUG}/5k`);
		await expect(page.getByRole('heading', { level: 1, name: COURSES[3].name })).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('share-course-shared-use')).toHaveText(
			'Organised groups use these paths on Saturday mornings. Give way, and avoid timing an effort through them.',
		);
		await expect(page.getByTestId('share-course-times')).toBeVisible();
	});
});
