import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun, deleteRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Races & courses (issue #1352): `/races` holds two sections, the race
 * calendar ("Upcoming races") and the park courses ("Run any time"), each
 * loading and failing on its own. The run-surface strip is five tabs in the
 * mobile order with no Parks tab, and `/parks` stays reachable directly, from
 * the section's "All park courses" link and from the Segments cross-link.
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

async function teardown(p: Planted | null) {
	if (!p) return;
	for (const id of p.runIds) await deleteRun(id).catch(() => {});
	const admin = getAdminClient();
	await admin.from('parks').delete().eq('id', p.parkId).then(() => {}, () => {});
	await admin.from('global_segments').delete().eq('id', p.segmentId).then(() => {}, () => {});
}

test.describe('races & courses', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the run-surface strip is five tabs in the mobile order, with no Parks tab', async ({ page }) => {
		await page.goto('/races');
		const strip = page.locator('nav.surface-tabs');
		await expect(strip).toBeVisible({ timeout: 10_000 });
		await expect(strip.getByRole('link')).toHaveText([
			'Runs',
			'Plans',
			'Races & courses',
			'Routes',
			'Segments',
		]);
		await expect(strip.getByRole('link', { name: 'Races & courses' })).toHaveAttribute('aria-current', 'page');
		await expect(strip.locator('a[href="/parks"]')).toHaveCount(0);
		await expect(page.getByRole('heading', { level: 1, name: 'Races & courses' })).toBeVisible();
		await expect(page).toHaveTitle(/^Races & courses/);
	});

	test('both sections render, and Run any time lists a park course with its season record', async ({ page }) => {
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
			await expect(upcoming.getByTestId('races-search')).toBeVisible();
			await expect(
				upcoming.getByTestId('races-results').or(upcoming.getByTestId('races-empty')),
			).toBeVisible({ timeout: 10_000 });

			const anyTime = page.getByTestId('races-any-time');
			await expect(anyTime.getByRole('heading', { level: 2, name: 'Run any time' })).toBeVisible();
			const card = anyTime.getByTestId('races-any-time-course').first();
			await expect(card).toContainText(planted.courseName, { timeout: 10_000 });
			await expect(card).toContainText(`${planted.parkName}, Alaska`);
			await expect(card).toContainText(/5\.00 (km|mi)|3\.11 mi/);
			await expect(card).toContainText('Loop');
			await expect(card.getByTestId('races-any-time-record')).toHaveText(
				new RegExp(`^\\d{4} record: 9:10 by ${holder?.display_name ?? ''}$`),
			);

			await card.click();
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
		await expect(page.getByTestId('races-any-time-all')).toHaveAttribute('href', '/parks');
	});

	test('failed records keep the courses listed, without records, and say so', async ({ page }) => {
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

	test('/parks is reachable from Run any time, from Segments and directly, with no strip of its own', async ({
		page,
	}) => {
		await page.goto('/races');
		await page.getByTestId('races-any-time-all').click();
		await page.waitForURL(/\/parks$/);
		await expect(page.getByRole('heading', { level: 1, name: 'Park courses' })).toBeVisible();
		await expect(page.locator('nav.surface-tabs')).toHaveCount(0);
		await expect(page.getByTestId('parks-back-to-races')).toHaveAttribute('href', '/races');

		await page.goto('/segments');
		await page.getByTestId('segments-parks-link').click();
		await page.waitForURL(/\/parks$/);
		await expect(page.getByRole('heading', { level: 1, name: 'Park courses' })).toBeVisible();

		await page.goto('/parks');
		await expect(page.getByRole('heading', { level: 1, name: 'Park courses' })).toBeVisible();
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
			await expect(first).toContainText(/0\.0 (km|mi) away/);
		} finally {
			await teardown(planted);
		}
	});
});
