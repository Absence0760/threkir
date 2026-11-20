import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * The park page's course preview and the back links around it: a card
 * previews its course on the page (the map, the facts, where to start and
 * an Open course button) with the choice kept in `?course=`, and back goes
 * where the reader came from, Races & courses with its `show=courses`
 * included, falling back to Races & courses on a direct link.
 *
 * Planted (service role) in one park under a unique slug at (37.2, -78.9),
 * which no seed row or other spec uses, and removed afterwards.
 */

const M_PER_DEG_LAT = 111_320;
const LAT = 37.2;
const LNG = -78.9;
const TAG = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
const PARK_SLUG = `e2e-preview-park-${TAG}`;
const PARK_NAME = `E2E Preview State Park ${TAG}`;
const PARK_PATH = `/parks/us-va/${PARK_SLUG}`;
const START_NOTE = 'Start at the boat-ramp lot.';

const COURSES = [
	// Trimmed to "Lakeside Loop" both would read the same, so each keeps its
	// distance and only the laps its chip states are dropped.
	{ slug: '5k', name: `Lakeside Loop ${TAG}, 5 km`, shown: `Lakeside Loop ${TAG}, 5 km`, distanceM: 5_000, laps: null },
	{ slug: '10k', name: `Lakeside Loop ${TAG}, 10 km (2 laps)`, shown: `Lakeside Loop ${TAG}, 10 km`, distanceM: 10_000, laps: 2 },
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
				waypoints: [
					{ lat: LAT, lng },
					{ lat: LAT + 800 / M_PER_DEG_LAT, lng },
					{ lat: LAT + 800 / M_PER_DEG_LAT, lng: lng + 0.005 },
					{ lat: LAT, lng },
				],
				distance_m: c.distanceM,
				elevation_m: 40,
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
			course_shape: 'loop',
			geometry_source: 'osm',
			checkpoints: [],
			laps: c.laps,
			route_guide: {
				version: 1,
				lang: 'en',
				getting_there: START_NOTE,
				steps: [
					{ kind: 'start', at_m: 0, name: 'Lake Trail' },
					{ kind: 'finish', at_m: c.distanceM },
				],
			},
		});
		if (course.error) throw course.error;
	}
});

test.afterAll(async () => {
	const admin = getAdminClient();
	if (parkId) await admin.from('parks').delete().eq('id', parkId);
	if (segmentIds.length) await admin.from('global_segments').delete().in('id', segmentIds);
});

test.describe('park preview and back', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('from Races & courses into a park and a course, back returns each step of the way', async ({ page }) => {
		// The Show switch writes `show=courses` without a navigation; back still keeps it.
		await page.goto('/races');
		await page.getByRole('group', { name: 'Show' }).getByRole('button', { name: 'Courses' }).click();
		await expect(page).toHaveURL(/\/races\?show=courses$/);
		const card = page.getByTestId('park-card').filter({ hasText: PARK_NAME });
		await card.click({ timeout: 15_000 });
		await page.waitForURL(`**${PARK_PATH}`);
		await expect(page.getByRole('heading', { level: 1, name: PARK_NAME })).toBeVisible();

		const parkBack = page.getByTestId('park-back');
		await expect(parkBack).toHaveAccessibleName('Races & courses');
		await expect(parkBack).toHaveAttribute('href', '/races?show=courses');

		await page.getByTestId('park-course-card').first().getByTestId('park-course-open').click();
		await page.waitForURL(`**${PARK_PATH}/5k`);
		const courseBack = page.getByTestId('park-course-back');
		await expect(courseBack).toHaveAccessibleName(PARK_NAME, { timeout: 15_000 });
		await courseBack.click();

		await page.waitForURL(`**${PARK_PATH}`);
		await expect(page.getByTestId('park-back')).toHaveAccessibleName('Races & courses');
		await page.getByTestId('park-back').click();
		await page.waitForURL('**/races?show=courses');
		await expect(page.getByRole('group', { name: 'Show' }).getByRole('button', { name: 'Courses' })).toHaveAttribute(
			'aria-pressed',
			'true',
		);
	});

	test('from the parks index, back names the index', async ({ page }) => {
		await page.goto('/parks');
		await page.getByTestId('park-card').filter({ hasText: PARK_NAME }).click({ timeout: 15_000 });
		await page.waitForURL(`**${PARK_PATH}`);
		await expect(page.getByTestId('park-back')).toHaveAccessibleName('All park courses');
		await expect(page.getByTestId('park-back')).toHaveAttribute('href', '/parks');
	});

	test('a direct link falls back: the park to Races & courses, the course to its park showing it', async ({ page }) => {
		await page.goto(PARK_PATH);
		await expect(page.getByTestId('park-back')).toHaveAccessibleName('Races & courses', { timeout: 15_000 });
		await expect(page.getByTestId('park-back')).toHaveAttribute('href', '/races?show=courses');

		await page.goto(`${PARK_PATH}/10k`);
		const courseBack = page.getByTestId('park-course-back');
		await expect(courseBack).toHaveAccessibleName(PARK_NAME, { timeout: 15_000 });
		await expect(courseBack).toHaveAttribute('href', `${PARK_PATH}?course=10k`);
		await courseBack.click();
		await page.waitForURL(`**${PARK_PATH}?course=10k`);
		await expect(page.getByTestId('park-course-preview')).toBeVisible({ timeout: 15_000 });
	});

	test('a card previews its course without leaving the page, and ?course= keeps it', async ({ page }) => {
		await page.goto(PARK_PATH);
		const cards = page.getByTestId('park-course-card');
		await expect(cards).toHaveCount(2, { timeout: 15_000 });
		// The laps the chip states are not repeated, and no two cards read the same.
		await expect(cards.locator('.list-card-title')).toHaveText([COURSES[0].shown, COURSES[1].shown]);

		const pick = cards.nth(1).locator('button.lc-tap');
		await expect(pick).not.toHaveAttribute('aria-pressed', 'true');
		await pick.click();
		await expect(page).toHaveURL(new RegExp(`${PARK_PATH}\\?course=10k$`));
		await expect(pick).toHaveAttribute('aria-pressed', 'true');

		const preview = page.getByTestId('park-course-preview');
		await expect(preview.getByRole('heading', { level: 2 })).toHaveText(COURSES[1].shown);
		await expect(preview.getByRole('heading', { level: 2 })).toBeFocused();
		await expect(preview.getByTestId('park-course-preview-distance')).toHaveText('10 km');
		await expect(preview.getByTestId('park-course-preview-laps')).toHaveText('2 × 5 km');
		await expect(preview.getByTestId('park-course-preview-shape')).toHaveText('Loop');
		await expect(preview.getByTestId('park-course-preview-start')).toHaveText(START_NOTE);
		const open = preview.getByRole('link', { name: 'Open course' });
		await expect(open).toHaveAttribute('href', `${PARK_PATH}/10k`);
		const directions = preview.getByRole('link', { name: 'Directions to the start and finish' });
		await expect(directions).toHaveAttribute('href', /destination=37\.20000%2C-78\.89000/);
		await expect(directions).toHaveAttribute('target', '_blank');

		// Tapping the picked card again keeps the preview: only Close or Escape close it.
		await pick.click();
		await expect(preview).toBeVisible();
		await expect(page).toHaveURL(new RegExp(`${PARK_PATH}\\?course=10k$`));

		await page.reload();
		await expect(page.getByTestId('park-course-preview').getByRole('heading', { level: 2 })).toHaveText(
			COURSES[1].shown,
			{ timeout: 15_000 },
		);

		await page.keyboard.press('Escape');
		await expect(page.getByTestId('park-course-preview')).toHaveCount(0);
		await expect(page).toHaveURL(new RegExp(`${PARK_PATH}$`));
		await expect(page.getByTestId('park-course-card').nth(1).locator('button.lc-tap')).toBeFocused();
	});

	test('the preview closes from its button, and Open course opens the course', async ({ page }) => {
		await page.goto(`${PARK_PATH}?course=5k`);
		const preview = page.getByTestId('park-course-preview');
		await expect(preview).toBeVisible({ timeout: 15_000 });
		await preview.getByRole('button', { name: 'Close preview' }).click();
		await expect(preview).toHaveCount(0);

		await page.getByTestId('park-course-card').first().locator('button.lc-tap').click();
		await page.getByTestId('park-course-preview').getByRole('link', { name: 'Open course' }).click();
		await page.waitForURL(`**${PARK_PATH}/5k`);
		// Back from the course pops to the park with the preview as it was.
		await page.getByTestId('park-course-back').click();
		await page.waitForURL(`**${PARK_PATH}?course=5k`);
		await expect(page.getByTestId('park-course-preview')).toBeVisible();
		await expect(page.getByTestId('park-back')).toHaveAccessibleName('Races & courses');
	});

	test('back closes an opened preview, and the park back link steps over it', async ({ page }) => {
		await page.goto('/races?show=courses');
		await page.getByTestId('park-card').filter({ hasText: PARK_NAME }).click({ timeout: 15_000 });
		await page.waitForURL(`**${PARK_PATH}`);
		await page.getByTestId('park-course-card').first().locator('button.lc-tap').click();
		await expect(page.getByTestId('park-course-preview')).toBeVisible();

		await page.goBack();
		await expect(page.getByTestId('park-course-preview')).toHaveCount(0);
		await expect(page).toHaveURL(new RegExp(`${PARK_PATH}$`));

		await page.getByTestId('park-course-card').nth(1).locator('button.lc-tap').click();
		await page.getByTestId('park-course-card').first().locator('button.lc-tap').click();
		await expect(page).toHaveURL(new RegExp(`${PARK_PATH}\\?course=5k$`));
		await page.getByTestId('park-back').click();
		await page.waitForURL('**/races?show=courses');
	});

	test('the first card and the map start on one line, and every card is one height', async ({ page }) => {
		await page.setViewportSize({ width: 1440, height: 900 });
		await page.goto(`${PARK_PATH}?course=10k`);
		const cards = page.getByTestId('park-course-card');
		await expect(cards).toHaveCount(2, { timeout: 15_000 });
		const map = page.locator('.map-frame');
		await expect(map).toBeVisible();
		const first = await cards.first().boundingBox();
		const frame = await map.boundingBox();
		expect(Math.abs((first?.y ?? 0) - (frame?.y ?? 99))).toBeLessThanOrEqual(1);
		const heights = await cards.evaluateAll((els) => els.map((el) => Math.round(el.getBoundingClientRect().height)));
		expect(new Set(heights).size).toBe(1);
		await expect(page.getByTestId('park-website')).toHaveCount(0);
	});
});
