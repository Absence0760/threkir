import { expect, test } from '../fixtures/test';

import { originOf } from '../fixtures/base-url';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * The park course pages as the owner reviewed them (issue #1352): a park's
 * courses sorted by distance with readable distances and a laps chip, the
 * index card's course count and distance range, the course page's map key,
 * its one credit line, its one primary action, an empty board that invites a
 * first run with its filters hidden, and the notices callout: the times
 * notice on every course and the give-way note on a course an organised group
 * shares (decisions § 2460), and the start and finish to copy or get
 * directions to.
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
				// The half runs out and back, so the trigger derives its finish
				// line at its start, facing the other way.
				waypoints: [
					{ lat: BASE_LAT, lng },
					{ lat: BASE_LAT + 1000 / M_PER_DEG_LAT, lng },
					...(c.shape === 'out_and_back' ? [{ lat: BASE_LAT, lng }] : []),
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
			// The half's last checkpoint is its turn, at the far end of the line.
			checkpoints:
				c.shape === 'out_and_back'
					? [
							{ lat: BASE_LAT + 500 / M_PER_DEG_LAT, lng },
							{ lat: BASE_LAT + 1000 / M_PER_DEG_LAT, lng },
						]
					: [{ lat: BASE_LAT + 500 / M_PER_DEG_LAT, lng }],
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

		// Signed in with no efforts planted, each course says there is no time yet.
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
		// The segment's stored lines (derived from its line by the trigger) are
		// drawn as a start box and a finish box, which the key names plainly,
		// and the block leads with one sentence and the way to the start.
		await expect(legend.locator('li[data-kind="startBox"]')).toHaveText('Start');
		await expect(legend.locator('li[data-kind="finishBox"]')).toHaveText('Finish');
		await expect(legend.locator('li[data-kind="start"]')).toHaveCount(0);
		await expect(page.getByTestId('park-course-ends-instruction')).toHaveText(
			'Start recording in the green box. Follow the arrows to the red box.',
		);
		const getDirections = page.getByTestId('park-course-ends-get-directions');
		await expect(getDirections).toHaveText(/Get directions to the start/);
		await expect(getDirections).toHaveAttribute('href', /destination=37\.40000%2C-78\.37000/);
		await expect(page.getByTestId('park-course-ends-coordinates')).not.toHaveAttribute('open');

		// One callout: two plain lines, safety first, the give-way note this
		// shared course carries between them, then the required notices as
		// one smaller line under them.
		const notices = page.getByTestId('park-course-notices');
		await expect(notices.locator('li')).toHaveText([
			"Follow the course line on the map and pass every checkpoint in order, or your time won't count.",
			'Organised groups use these paths on Saturday mornings. Give way, and avoid timing an effort through them.',
			'Finish before the park closes.',
		]);
		await expect(notices.getByTestId('park-course-open-trail')).toHaveText(
			'A time trial on open trails, not a race. Nobody marshals it.',
		);
		await expect(notices.locator('li').first()).toHaveAttribute('data-testid', 'park-course-safety');
		await expect(notices.getByTestId('park-course-shared-use')).toBeVisible();
		await expect(notices.getByTestId('park-course-times')).toBeVisible();
		await expect(notices.getByTestId('park-course-not-affiliated')).toBeVisible();

		// No route to navigate, so the way to the start is the one filled
		// action and the GPX download an outline one.
		await expect(page.getByTestId('park-course-navigate')).toHaveCount(0);
		await expect(page.getByTestId('park-course-gpx')).toHaveClass(/btn-outline/);
		await expect(page.getByTestId('park-course-ends-get-directions')).toHaveClass(/btn-primary/);
		await expect(page.locator('.course-layout .btn-primary')).toHaveCount(1);

		// No times on any board: an invitation, and nothing to switch between.
		await expect(page.getByTestId('park-board-invite').getByRole('heading')).toHaveText(
			'No times yet. Run it with Threkir and yours shows up here.',
		);
		await expect(page.getByTestId('park-board-fastest')).toHaveCount(0);
		await expect(page.getByTestId('park-season-all-time')).toHaveCount(0);
		await expect(page.getByTestId('park-board-filters')).toHaveCount(0);
		await expect(page.getByTestId('park-board-compare')).toHaveCount(0);
	});

	test('the course page gives its start and finish to copy and get directions to; a loop gives one point', async ({
		page,
		context,
		baseURL,
	}) => {
		await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: originOf(baseURL) });
		await page.goto(`/parks/us-va/${PARK_SLUG}/50k`);
		const ends = page.getByTestId('park-course-ends');
		await expect(ends).toBeVisible({ timeout: 15_000 });
		await expect(ends.getByRole('heading', { name: 'Start and finish points' })).toBeVisible();
		// The coordinates sit folded under the sentence and the directions button.
		await ends.getByText('Coordinates', { exact: true }).click();
		await expect(ends.getByTestId('park-course-ends-start-coords')).toHaveText('37.40000, -78.38000');
		await expect(ends.getByTestId('park-course-ends-finish-coords')).toHaveText('37.40898, -78.38000');
		await expect(ends.getByTestId('park-course-ends-startFinish')).toHaveCount(0);

		const copy = ends.getByRole('button', { name: 'Copy finish coordinates' });
		await copy.click();
		await expect(ends.getByTestId('park-course-ends-finish-status')).toHaveText('Coordinates copied');
		expect(await page.evaluate(() => navigator.clipboard.readText())).toBe('37.40898, -78.38000');

		const directions = ends.getByRole('link', { name: 'Directions to the start', exact: true });
		await expect(directions).toHaveAttribute('href', /destination=37\.40000%2C-78\.38000/);
		await expect(directions).toHaveAttribute('target', '_blank');

		await page.goto(`/parks/us-va/${PARK_SLUG}/5k`);
		const loop = page.getByTestId('park-course-ends');
		await loop.getByText('Coordinates', { exact: true }).click({ timeout: 15_000 });
		await expect(loop.getByTestId('park-course-ends-startFinish')).toContainText('Start and finish', { timeout: 15_000 });
		await expect(loop.getByTestId('park-course-ends-start')).toHaveCount(0);
		await expect(loop.getByRole('button', { name: 'Copy start and finish coordinates' })).toBeVisible();
	});

	test('a refused copy says so and leaves the coordinates to select', async ({ page }) => {
		await page.addInitScript(() => {
			Object.defineProperty(navigator, 'clipboard', {
				value: { writeText: () => Promise.reject(new Error('denied')) },
			});
		});
		await page.goto(`/parks/us-va/${PARK_SLUG}/50k`);
		const ends = page.getByTestId('park-course-ends');
		await ends.getByText('Coordinates', { exact: true }).click({ timeout: 15_000 });
		await ends.getByRole('button', { name: 'Copy start coordinates' }).click();
		await expect(ends.getByTestId('park-course-ends-start-status')).toHaveText(
			"Couldn't copy the coordinates. Select them and copy them yourself.",
		);
		await expect(ends.getByTestId('park-course-ends-start-coords')).toHaveText('37.40000, -78.38000');
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

	test('an out-and-back has one green-and-red box and a Turn around mark', async ({ page }) => {
		await page.goto(`/parks/us-va/${PARK_SLUG}/half`);
		await expect(page.getByRole('heading', { level: 1, name: COURSES[4].name })).toBeVisible({ timeout: 15_000 });
		const legend = page.getByTestId('park-course-legend');
		await expect(legend.locator('li[data-kind="startFinishBox"]')).toHaveText('Start and finish');
		await expect(legend.locator('li[data-kind="startBox"]')).toHaveCount(0);
		await expect(legend.locator('li[data-kind="finishBox"]')).toHaveCount(0);
		await expect(legend.locator('li[data-kind="turnaround"]')).toHaveText('Turn around here: your run must pass it');
		await expect(page.getByTestId('park-course-ends-instruction')).toHaveText(
			'Start recording in the green-and-red box. Follow the arrows to the Turn around mark, then back to the box.',
		);
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
