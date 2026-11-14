import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun, deleteRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Races & courses (issue #1352): `/races` holds two sections, the race
 * calendar ("Upcoming races") and the park courses ("Run any time"), each
 * loading and failing on its own. The run-surface strip is five tabs in the
 * mobile order with no Parks tab, and `/parks` stays reachable directly and
 * from the section's "See all N courses" heading link, which shows only when
 * the list is cut short (issue #1374). One search finds races by name and
 * park courses by name, park and place, in every view.
 *
 * The park is planted in region US-AK so it sorts first in the stable order
 * whatever other parks the local catalogue holds, and its course start is the
 * position the location test grants, so it is nearest there too.
 */

const uniq = () => `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
const M_PER_DEG_LAT = 111_320;
const START = { lat: 61.2, lng: -149.9 };

interface Planted {
	parkId: string;
	parkSlug: string;
	parkName: string;
	segmentId: string;
	courseName: string;
	runIds: string[];
}

async function plantCourse(): Promise<Planted> {
	const admin = getAdminClient();
	const tag = uniq();
	const parkSlug = `e2e-any-time-${tag}`;
	const parkName = `AAA E2E Any Time Park ${tag}`;
	const courseName = `E2E Any Time Loop ${tag}`;
	const { data: seg, error: segErr } = await admin
		.from('global_segments')
		.insert({
			name: courseName,
			waypoints: [
				{ lat: START.lat, lng: START.lng },
				{ lat: START.lat + 5000 / M_PER_DEG_LAT, lng: START.lng },
			],
			distance_m: 5000,
			surface: 'trail',
			country_code: 'US',
		})
		.select('id')
		.single();
	if (segErr) throw segErr;
	const { data: park, error: parkErr } = await admin
		.from('parks')
		.insert({
			slug: parkSlug,
			name: parkName,
			agency: 'state',
			region_code: 'US-AK',
			country_code: 'US',
			timezone: 'America/Anchorage',
		})
		.select('id')
		.single();
	if (parkErr) throw parkErr;
	const { error: courseErr } = await admin.from('park_courses').insert({
		park_id: park.id,
		global_segment_id: seg.id,
		slug: 'any-time-loop',
		course_shape: 'loop',
		geometry_source: 'osm',
	});
	if (courseErr) throw courseErr;
	return { parkId: park.id, parkSlug, parkName, segmentId: seg.id, courseName, runIds: [] };
}

async function plantEffort(p: Planted, userId: string, timeS: number) {
	const startedAt = new Date().toISOString();
	const runId = await insertRun({
		user_id: userId,
		started_at: startedAt,
		duration_s: timeS + 60,
		distance_m: 5000,
		is_public: true,
	});
	p.runIds.push(runId);
	const { error } = await getAdminClient().from('global_segment_efforts').insert({
		global_segment_id: p.segmentId,
		run_id: runId,
		user_id: userId,
		time_seconds: timeS,
		started_at: startedAt,
		matched_by: 'gate',
	});
	if (error) throw error;
}

async function plantCourses(n: number): Promise<Planted[]> {
	const planted: Planted[] = [];
	for (let i = 0; i < n; i++) planted.push(await plantCourse());
	return planted;
}

async function teardown(p: Planted | null) {
	if (!p) return;
	for (const id of p.runIds) await deleteRun(id).catch(() => {});
	const admin = getAdminClient();
	await admin.from('parks').delete().eq('id', p.parkId).then(() => {}, () => {});
	await admin.from('global_segments').delete().eq('id', p.segmentId).then(() => {}, () => {});
}

test.describe('races & courses', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the run-surface strip is four tabs in the mobile order, with no Parks or Segments tab', async ({ page }) => {
		await page.goto('/races');
		const strip = page.locator('nav.surface-tabs');
		await expect(strip).toBeVisible({ timeout: 10_000 });
		// Segments is Routes → Explore since issue #1374 (owner decision 1).
		await expect(strip.getByRole('link')).toHaveText([
			'Runs',
			'Plans',
			'Races & courses',
			'Routes',
		]);
		await expect(strip.getByRole('link', { name: 'Races & courses' })).toHaveAttribute('aria-current', 'page');
		await expect(strip.locator('a[href="/parks"]')).toHaveCount(0);
		await expect(page.getByRole('heading', { level: 1, name: 'Races & courses' })).toBeVisible();
		await expect(page).toHaveTitle(/^Races & courses/);
	});

	test('both sections render, and Run any time lists a park course with its fastest time this season', async ({ page }) => {
		let planted: Planted | null = null;
		try {
			planted = await plantCourse();
			await plantEffort(planted, USER_A.id, 600);
			await plantEffort(planted, USER_B.id, 550);
			const { data: holder } = await getAdminClient()
				.from('user_profiles')
				.select('display_name')
				.eq('id', USER_B.id)
				.single();

			await page.goto('/races');
			const upcoming = page.getByTestId('races-upcoming');
			await expect(upcoming.getByRole('heading', { level: 2, name: 'Upcoming races' })).toBeVisible();
			await expect(page.getByTestId('races-search')).toBeVisible();
			await expect(
				upcoming.getByTestId('races-results').or(upcoming.getByTestId('races-empty')),
			).toBeVisible({ timeout: 10_000 });

			const anyTime = page.getByTestId('races-any-time');
			await expect(anyTime.getByRole('heading', { level: 2, name: 'Run any time' })).toBeVisible();
			const card = anyTime.getByTestId('races-any-time-course').first();
			await expect(card).toContainText(planted.courseName, { timeout: 10_000 });
			await expect(card).toContainText(`${planted.parkName}, Alaska`);
			const meta = card.getByTestId('races-any-time-meta');
			await expect(card.getByTestId('races-any-time-distance')).toHaveText(/^(5 km|3\.1 mi)$/);
			await expect(meta).not.toContainText(/\d\.\d\d/);
			await expect(meta).not.toContainText('Loop');
			await expect(card.getByTestId('races-any-time-laps')).toHaveCount(0);
			await expect(card.getByTestId('races-any-time-record')).toHaveText(
				new RegExp(`^Fastest in \\d{4}: 9:10 by ${holder?.display_name ?? ''}$`),
			);

			await card.getByTestId('races-any-time-course-link').click();
			await page.waitForURL(`**/parks/us-ak/${planted.parkSlug}/any-time-loop`);
			await expect(page.getByRole('heading', { level: 1, name: planted.courseName })).toBeVisible();
		} finally {
			await teardown(planted);
		}
	});

	test('a course with no time this season says so', async ({ page }) => {
		let planted: Planted | null = null;
		try {
			planted = await plantCourse();
			await page.goto('/races');
			const card = page.getByTestId('races-any-time-course').first();
			await expect(card).toContainText(planted.courseName, { timeout: 10_000 });
			await expect(card.getByTestId('races-any-time-record')).toHaveText(
				'No time yet this season. Yours could be the first.',
			);
		} finally {
			await teardown(planted);
		}
	});

	test('a failed race search leaves Run any time standing', async ({ page }) => {
		await page.route('**/rest/v1/rpc/search_race_listings*', (route) =>
			route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' }),
		);
		await page.goto('/races');
		await expect(page.getByTestId('races-error')).toBeVisible({ timeout: 10_000 });
		const anyTime = page.getByTestId('races-any-time');
		await expect(
			anyTime.getByTestId('races-any-time-list').or(anyTime.getByTestId('races-any-time-empty')),
		).toBeVisible();
		await expect(page.getByTestId('races-any-time-error')).toHaveCount(0);
	});

	test('a failed course read leaves the race calendar standing, and Retry recovers', async ({ page }) => {
		let fail = true;
		await page.route('**/rest/v1/park_courses*', (route) =>
			fail
				? route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' })
				: route.fallback(),
		);
		await page.goto('/races');
		const error = page.getByTestId('races-any-time-error');
		await expect(error).toBeVisible({ timeout: 10_000 });
		await expect(error).toContainText("Couldn't load park courses.");
		await expect(
			page.getByTestId('races-results').or(page.getByTestId('races-empty')),
		).toBeVisible();
		await expect(page.getByTestId('races-error')).toHaveCount(0);

		fail = false;
		await error.getByRole('button', { name: 'Retry' }).click();
		await expect(error).toHaveCount(0);
		await expect(
			page.getByTestId('races-any-time-list').or(page.getByTestId('races-any-time-empty')),
		).toBeVisible();
	});

	test('no park courses shows the shared empty state', async ({ page }) => {
		await page.route('**/rest/v1/park_courses*', (route) =>
			route.fulfill({ status: 200, contentType: 'application/json', body: '[]' }),
		);
		await page.goto('/races');
		const empty = page.getByTestId('races-any-time-empty');
		await expect(empty).toBeVisible({ timeout: 10_000 });
		await expect(empty).toContainText('No park courses yet.');
		await expect(page.getByTestId('races-any-time-all')).toHaveCount(0);
	});

	test('failed fastest times keep the courses listed, without them, and say so', async ({ page }) => {
		let planted: Planted | null = null;
		try {
			planted = await plantCourse();
			await page.route('**/rest/v1/rpc/park_course_records*', (route) =>
				route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' }),
			);
			await page.goto('/races');
			await expect(page.getByTestId('races-any-time-records-failed')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('races-any-time-course').first()).toContainText(planted.courseName);
			await expect(page.getByTestId('races-any-time-record')).toHaveCount(0);
		} finally {
			await teardown(planted);
		}
	});

	test('the Show switch hides either section, and the URL says which', async ({ page }) => {
		await page.goto('/races');
		const show = page.getByRole('group', { name: 'Show' });
		const all = show.getByRole('button', { name: 'All' });
		const races = show.getByRole('button', { name: 'Races' });
		const courses = show.getByRole('button', { name: 'Courses' });
		await expect(all).toHaveAttribute('aria-pressed', 'true');
		await expect(page.getByTestId('races-upcoming')).toBeVisible();
		await expect(page.getByTestId('races-any-time')).toBeVisible();

		await courses.click();
		await expect(page).toHaveURL(/\/races\?show=courses$/);
		await expect(courses).toHaveAttribute('aria-pressed', 'true');
		await expect(all).toHaveAttribute('aria-pressed', 'false');
		await expect(page.getByTestId('races-upcoming')).toHaveCount(0);
		await expect(page.getByTestId('races-filters-toggle')).toHaveCount(0);
		const anyTime = page.getByTestId('races-any-time');
		await expect(anyTime).toBeVisible();
		await expect(anyTime.getByTestId('races-near')).toBeVisible();
		await expect(anyTime.getByTestId('races-use-location')).toBeVisible();
		// Every course is listed here, so there is no "See all".
		await expect(anyTime.getByTestId('races-any-time-all')).toHaveCount(0);
		// The search stays, and says what it finds in this view.
		await expect(page.getByTestId('races-search')).toHaveAttribute('placeholder', 'Search parks and courses…');

		await races.click();
		await expect(page).toHaveURL(/\/races\?show=races$/);
		await expect(page.getByTestId('races-any-time')).toHaveCount(0);
		await expect(page.getByTestId('races-upcoming')).toBeVisible();
		await expect(page.getByTestId('races-filters-toggle')).toBeVisible();

		await all.click();
		await expect(page).toHaveURL(/\/races$/);
		await expect(page.getByTestId('races-upcoming')).toBeVisible();
		await expect(page.getByTestId('races-any-time')).toBeVisible();
	});

	test('a ?show= link opens that view, and a value it does not know opens both', async ({ page }) => {
		await page.goto('/races?show=courses');
		await expect(page.getByTestId('races-show-courses')).toHaveAttribute('aria-pressed', 'true');
		await expect(page.getByTestId('races-any-time')).toBeVisible();
		await expect(page.getByTestId('races-upcoming')).toHaveCount(0);

		await page.goto('/races?show=races');
		await expect(page.getByTestId('races-show-races')).toHaveAttribute('aria-pressed', 'true');
		await expect(page.getByTestId('races-any-time')).toHaveCount(0);

		await page.goto('/races?show=parks');
		await expect(page.getByTestId('races-show-all')).toHaveAttribute('aria-pressed', 'true');
		await expect(page.getByTestId('races-upcoming')).toBeVisible();
		await expect(page.getByTestId('races-any-time')).toBeVisible();
	});

	test('Courses lists every course, where both sections stop at eight', async ({ page }) => {
		let planted: Planted[] = [];
		try {
			planted = await plantCourses(9);

			await page.goto('/races');
			const cards = page.getByTestId('races-any-time-course');
			await expect(cards.first()).toBeVisible({ timeout: 10_000 });
			await expect(cards).toHaveCount(8);
			const seeAll = page.getByTestId('races-any-time-all');
			await expect(seeAll).toHaveText(/^See all \d+ courses/);
			await expect(seeAll).toHaveAttribute('href', '/parks');

			await page.getByTestId('races-show-courses').click();
			await expect(seeAll).toHaveCount(0);
			for (const p of planted) {
				await expect(cards.filter({ hasText: p.courseName })).toHaveCount(1, { timeout: 10_000 });
			}
			expect(await cards.count()).toBeGreaterThan(8);
		} finally {
			for (const p of planted) await teardown(p);
		}
	});

	test('back from a course returns to the Courses view', async ({ page }) => {
		let planted: Planted | null = null;
		try {
			planted = await plantCourse();
			await page.goto('/races');
			await page.getByTestId('races-show-courses').click();
			await expect(page).toHaveURL(/\?show=courses$/);
			await page
				.getByTestId('races-any-time-course')
				.filter({ hasText: planted.courseName })
				.getByTestId('races-any-time-course-link')
				.click();
			await page.waitForURL(`**/parks/us-ak/${planted.parkSlug}/any-time-loop`);
			await page.goBack();
			await expect(page).toHaveURL(/\/races\?show=courses$/);
			await expect(page.getByTestId('races-show-courses')).toHaveAttribute('aria-pressed', 'true');
			await expect(page.getByTestId('races-upcoming')).toHaveCount(0);
		} finally {
			await teardown(planted);
		}
	});

	test('Park courses on Segments opens Races & courses on its Courses view', async ({ page }) => {
		await page.goto('/segments');
		const link = page.getByTestId('segments-parks-link');
		await expect(link).toHaveAttribute('href', '/races?show=courses');
		await link.click();
		await page.waitForURL(/\/races\?show=courses$/);
		await expect(page.getByTestId('races-show-courses')).toHaveAttribute('aria-pressed', 'true');
		await expect(page.getByTestId('races-upcoming')).toHaveCount(0);
		await expect(page.getByTestId('races-any-time')).toBeVisible();
	});

	test('Courses leads with the parks, each opening its park page; All has no park row', async ({ page }) => {
		let planted: Planted | null = null;
		try {
			planted = await plantCourse();
			await page.goto('/races');
			await expect(page.getByTestId('races-any-time-course').first()).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('races-any-time-parks')).toHaveCount(0);

			await page.getByTestId('races-show-courses').click();
			const parks = page.getByTestId('races-any-time-parks');
			await expect(page.getByRole('heading', { level: 3, name: 'Parks' })).toBeVisible();
			const card = parks.getByTestId('park-card').filter({ hasText: planted.parkName });
			await expect(card).toHaveAttribute('href', `/parks/us-ak/${planted.parkSlug}`);
			await expect(card.getByTestId('park-card-facts')).toContainText('1 course');
			await card.click();
			await page.waitForURL(`**/parks/us-ak/${planted.parkSlug}`);
			await expect(page.getByRole('heading', { level: 1, name: planted.parkName })).toBeVisible();
		} finally {
			await teardown(planted);
		}
	});

	test('a course card names its park as a link of its own, to the park page', async ({ page }) => {
		let planted: Planted | null = null;
		try {
			planted = await plantCourse();
			await page.goto('/races');
			const card = page.getByTestId('races-any-time-course').filter({ hasText: planted.courseName });
			const parkLink = card.getByTestId('races-any-time-park-link');
			await expect(parkLink).toHaveText(`${planted.parkName}, Alaska`, { timeout: 10_000 });
			await expect(parkLink).toHaveAccessibleName(`${planted.parkName}, Alaska: park page`);
			await parkLink.click();
			await page.waitForURL(`**/parks/us-ak/${planted.parkSlug}`);
		} finally {
			await teardown(planted);
		}
	});

	test('/parks is reachable from a cut-short Run any time and directly, with no strip of its own', async ({
		page,
	}) => {
		let planted: Planted[] = [];
		try {
			planted = await plantCourses(9);
			await page.goto('/races');
			await page.getByTestId('races-any-time-all').click({ timeout: 10_000 });
			await page.waitForURL(/\/parks$/);
			await expect(page.getByRole('heading', { level: 1, name: 'Park courses' })).toBeVisible();
			await expect(page.locator('nav.surface-tabs')).toHaveCount(0);
			await expect(page.getByTestId('parks-back-to-races')).toHaveAttribute('href', '/races');

			await page.goto('/parks');
			await expect(page.getByRole('heading', { level: 1, name: 'Park courses' })).toBeVisible();
		} finally {
			for (const p of planted) await teardown(p);
		}
	});

	test('the search finds park courses by name, park and place, in every view, and says when none match', async ({
		page,
	}) => {
		let planted: Planted[] = [];
		try {
			planted = await plantCourses(2);
			const [a, b] = planted;
			await page.goto('/races');
			const search = page.getByTestId('races-search');
			await expect(search).toHaveAttribute('placeholder', 'Search races, parks and courses…');
			const cards = page.getByTestId('races-any-time-course');
			await expect(cards.first()).toBeVisible({ timeout: 10_000 });

			// By course name: the other planted course drops out.
			await search.fill(a.courseName.toUpperCase());
			await expect(cards).toHaveCount(1);
			await expect(cards.first()).toContainText(a.courseName);

			// By park name plus place, word by word, in any case.
			await search.fill(`alaska ${b.parkName.split(' ').pop()}`);
			await expect(cards).toHaveCount(1);
			await expect(cards.first()).toContainText(b.courseName);

			// The search stays when Courses is chosen, and still filters.
			await page.getByTestId('races-show-courses').click();
			await expect(search).toHaveValue(`alaska ${b.parkName.split(' ').pop()}`);
			await expect(cards).toHaveCount(1);
			await expect(page.getByTestId('races-any-time-parks').getByTestId('park-card')).toHaveCount(1);

			// Nothing matches: the empty state names the search and clears it.
			await search.fill('zzz-no-such-course');
			const none = page.getByTestId('races-any-time-no-match');
			await expect(none).toContainText('No courses match “zzz-no-such-course”');
			await none.getByTestId('races-any-time-clear-search').click();
			await expect(search).toHaveValue('');
			await expect(cards.filter({ hasText: a.courseName })).toHaveCount(1);
		} finally {
			for (const p of planted) await teardown(p);
		}
	});

	test('/parks has a search of its own, which a ?q= link opens on', async ({ page }) => {
		let planted: Planted[] = [];
		try {
			planted = await plantCourses(2);
			const [a, b] = planted;
			await page.goto(`/parks?q=${encodeURIComponent(a.courseName)}`);
			const search = page.getByTestId('parks-search');
			await expect(search).toHaveValue(a.courseName);
			const cards = page.getByTestId('park-card');
			await expect(cards.filter({ hasText: a.parkName })).toHaveCount(1, { timeout: 10_000 });
			await expect(cards.filter({ hasText: b.parkName })).toHaveCount(0);

			await search.fill('zzz-no-such-park');
			await expect(page.getByTestId('parks-no-match')).toContainText('No parks or courses match “zzz-no-such-park”');
			await page.getByTestId('parks-clear-search').click();
			await expect(cards.filter({ hasText: b.parkName })).toHaveCount(1);
		} finally {
			for (const p of planted) await teardown(p);
		}
	});
});

test.describe('races & courses, with a location', () => {
	test.use({
		storageState: USER_A.storageStatePath,
		permissions: ['geolocation'],
		geolocation: { latitude: START.lat, longitude: START.lng },
	});

	test('Use my location orders Run any time nearest first, with the distance away', async ({ page }) => {
		let planted: Planted | null = null;
		try {
			planted = await plantCourse();
			await page.goto('/races');
			await page.getByTestId('races-filters-toggle').click();
			await page.getByTestId('races-use-location').click();
			const first = page.getByTestId('races-any-time-course').first();
			await expect(first).toContainText(planted.courseName, { timeout: 10_000 });
			await expect(first).toContainText(/(^|\D)0 (km|mi) away/);
		} finally {
			await teardown(planted);
		}
	});

	test('in the Courses view, Use my location sits with the courses and orders them', async ({ page }) => {
		let planted: Planted | null = null;
		try {
			planted = await plantCourse();
			await page.goto('/races?show=courses');
			const anyTime = page.getByTestId('races-any-time');
			await anyTime.getByTestId('races-use-location').click();
			await expect(anyTime.getByTestId('races-near-clear')).toContainText('Near me');
			const first = anyTime.getByTestId('races-any-time-course').first();
			await expect(first).toContainText(planted.courseName, { timeout: 10_000 });
			await expect(first).toContainText(/(^|\D)0 (km|mi) away/);

			await anyTime.getByTestId('races-near-clear').click();
			await expect(anyTime.getByTestId('races-near-clear')).toHaveCount(0);
			await expect(first).not.toContainText(/ away/);
		} finally {
			await teardown(planted);
		}
	});
});
