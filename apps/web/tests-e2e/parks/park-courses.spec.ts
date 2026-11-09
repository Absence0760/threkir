import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun, deleteRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';
import { readRows } from '../fixtures/db-read';

/**
 * Park courses (issue #1313, decisions § 2383): the /parks index, a park,
 * and a course with its fastest and most-completions boards, this season and
 * all time; the signed-out view; and the checkpoint rule on the scorer.
 *
 * Every row is planted here (service role) under a unique slug, so the spec
 * does not lean on the seed's fixture park and leaves nothing behind.
 */

const uniq = () => `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
const M_PER_DEG_LAT = 111_320;
const DAY_MS = 86_400_000;

interface Planted {
	parkId: string;
	parkSlug: string;
	parkName: string;
	segmentId: string;
	courseSlug: string;
	courseName: string;
	runIds: string[];
}

async function plantCourse(opts: {
	baseLat: number;
	lng: number;
	lengthM: number;
	checkpoints: { lat: number; lng: number }[];
}): Promise<Planted> {
	const admin = getAdminClient();
	const tag = uniq();
	const parkSlug = `e2e-park-${tag}`;
	const parkName = `E2E State Park ${tag}`;
	const courseName = `E2E Lake Loop ${tag}`;
	const { data: seg, error: segErr } = await admin
		.from('global_segments')
		.insert({
			name: courseName,
			waypoints: [
				{ lat: opts.baseLat, lng: opts.lng },
				{ lat: opts.baseLat + opts.lengthM / M_PER_DEG_LAT, lng: opts.lng },
			],
			distance_m: opts.lengthM,
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
			region_code: 'US-VA',
			country_code: 'US',
			timezone: 'America/New_York',
		})
		.select('id')
		.single();
	if (parkErr) throw parkErr;
	const { error: courseErr } = await admin.from('park_courses').insert({
		park_id: park.id,
		global_segment_id: seg.id,
		slug: 'lake-loop',
		course_shape: 'out_and_back',
		geometry_source: 'osm',
		checkpoints: opts.checkpoints,
	});
	if (courseErr) throw courseErr;
	return {
		parkId: park.id,
		parkSlug,
		parkName,
		segmentId: seg.id,
		courseSlug: 'lake-loop',
		courseName,
		runIds: [],
	};
}

async function plantEffort(p: Planted, userId: string, timeS: number, startedAt: Date) {
	const runId = await insertRun({
		user_id: userId,
		started_at: startedAt.toISOString(),
		duration_s: timeS + 60,
		distance_m: 1000,
		is_public: true,
	});
	p.runIds.push(runId);
	const { error } = await getAdminClient().from('global_segment_efforts').insert({
		global_segment_id: p.segmentId,
		run_id: runId,
		user_id: userId,
		time_seconds: timeS,
		started_at: startedAt.toISOString(),
		matched_by: 'gate',
	});
	if (error) throw error;
}

async function teardown(p: Planted | null) {
	if (!p) return;
	for (const id of p.runIds) await deleteRun(id).catch(() => {});
	const admin = getAdminClient();
	// The park cascades its course; the segment cascades its efforts.
	await admin.from('parks').delete().eq('id', p.parkId).then(() => {}, () => {});
	await admin.from('global_segments').delete().eq('id', p.segmentId).then(() => {}, () => {});
}

test.describe('park courses', () => {
	test.describe('signed in', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('index → park → course, with season and all-time boards', async ({ page }) => {
			let planted: Planted | null = null;
			try {
				planted = await plantCourse({ baseLat: 37.2, lng: -78.9, lengthM: 1000, checkpoints: [] });
				const now = new Date();
				// A: 10:00 this season, 8:20 more than a year ago. B: 9:10 this season.
				await plantEffort(planted, USER_A.id, 600, now);
				await plantEffort(planted, USER_A.id, 500, new Date(now.getTime() - 400 * DAY_MS));
				await plantEffort(planted, USER_B.id, 550, now);

				await page.goto('/parks');
				await expect(page.getByRole('heading', { level: 1, name: 'Park courses' })).toBeVisible();
				await expect(page.getByText(/Run one whenever the park is open/)).toBeVisible();
				await page.getByRole('link', { name: new RegExp(planted.parkName) }).click();
				await page.waitForURL(`**/parks/us-va/${planted.parkSlug}`);
				await expect(page.getByRole('heading', { level: 1, name: planted.parkName })).toBeVisible();
				await expect(page.getByTestId('park-not-affiliated')).toContainText(
					'not organised, sponsored or endorsed by the park',
				);

				await page.getByRole('link', { name: new RegExp(planted.courseName) }).click();
				await page.waitForURL(`**/parks/us-va/${planted.parkSlug}/lake-loop`);
				await expect(page.getByRole('heading', { level: 1, name: planted.courseName })).toBeVisible();
				await expect(page.getByTestId('park-course-safety')).toBeVisible();
				await expect(page.getByTestId('park-course-attribution')).toContainText('OpenStreetMap');
				await expect(page.getByTestId('park-course-not-affiliated')).toContainText(
					'Park rules, hours, fees and closures apply.',
				);
				// 1 km is not a long course.
				await expect(page.getByTestId('park-course-long')).toHaveCount(0);

				const board = page.getByTestId('park-board');
				const rows = board.locator('li');
				// This season: B's 9:10 leads A's 10:00; A's older 8:20 is not counted.
				await expect(rows).toHaveCount(2);
				await expect(rows.nth(0).locator('.value')).toHaveText('9:10');
				await expect(rows.nth(1).locator('.value')).toHaveText('10:00');
				await expect(rows.nth(1)).toHaveClass(/viewer/);

				await page.getByTestId('park-season-all-time').click();
				await expect(rows.nth(0).locator('.value')).toHaveText('8:20');
				await expect(rows.nth(0)).toHaveClass(/viewer/);
				await expect(rows.nth(1).locator('.value')).toHaveText('9:10');

				await page.getByTestId('park-board-completions').click();
				await expect(rows).toHaveCount(2);
				await expect(rows.nth(0).locator('.value')).toHaveText('2 days');
				await expect(rows.nth(0)).toHaveClass(/viewer/);

				await page.getByTestId('park-season-this-year').click();
				await expect(rows.nth(0).locator('.value')).toHaveText('1 day');
				await expect(rows.nth(1).locator('.value')).toHaveText('1 day');
			} finally {
				await teardown(planted);
			}
		});

		test('a run that skips a checkpoint earns no time; one that passes it does', async ({ page }) => {
			const BASE_LAT = 37.6;
			const LNG = -79.4;
			const LEN = 800;
			let onPath: Planted | null = null;
			let offPath: Planted | null = null;
			let runId = '';
			try {
				// Same line twice: one course's checkpoint sits on it, the other's
				// ~1 km east, on the far side of a cut the run never makes.
				onPath = await plantCourse({
					baseLat: BASE_LAT,
					lng: LNG,
					lengthM: LEN,
					checkpoints: [{ lat: BASE_LAT + 400 / M_PER_DEG_LAT, lng: LNG }],
				});
				offPath = await plantCourse({
					baseLat: BASE_LAT,
					lng: LNG,
					lengthM: LEN,
					checkpoints: [{ lat: BASE_LAT + 400 / M_PER_DEG_LAT, lng: LNG + 0.011 }],
				});

				const start = Date.parse('2026-05-01T08:00:00Z');
				const track: { lat: number; lng: number; ts: string }[] = [];
				// From 40 m before the start line, which the course inherits from
				// its segment (decisions § 2402) and the run must cross.
				for (let d = -40; d <= 900; d += 20) {
					track.push({
						lat: BASE_LAT + d / M_PER_DEG_LAT,
						lng: LNG,
						ts: new Date(start + ((d + 40) / 2) * 1000).toISOString(),
					});
				}
				runId = await insertRun({
					user_id: USER_A.id,
					started_at: '2026-05-01T08:00:00Z',
					duration_s: 470,
					distance_m: 940,
					is_public: true,
					track,
				});

				await page.goto(`/runs/${runId}`);
				await expect(
					page.locator(`.efforts a.effort-row[href="/segments/${onPath.segmentId}"]`),
				).toBeVisible({ timeout: 15_000 });

				// One sweep wrote every match in a single batch, so the on-path
				// effort being present is the moment the off-path one would be too.
				const admin = getAdminClient();
				const on = await readRows(
					'global_segment_efforts by global_segment_id',
					admin.from('global_segment_efforts').select('id').eq('global_segment_id', onPath.segmentId),
				);
				expect(on.length).toBe(1);
				const off = await readRows(
					'global_segment_efforts by global_segment_id',
					admin.from('global_segment_efforts').select('id').eq('global_segment_id', offPath.segmentId),
				);
				expect(off.length).toBe(0);
			} finally {
				if (runId) await deleteRun(runId).catch(() => {});
				await teardown(onPath);
				await teardown(offPath);
			}
		});
	});

	test.describe('signed out', () => {
		test.use({ storageState: { cookies: [], origins: [] } });

		test('the course page shows the course and asks for a sign-in before the boards', async ({
			page,
		}) => {
			let planted: Planted | null = null;
			try {
				planted = await plantCourse({ baseLat: 37.9, lng: -79.9, lengthM: 1200, checkpoints: [] });
				await page.goto(`/parks/us-va/${planted.parkSlug}/lake-loop`);
				await expect(page.getByRole('heading', { level: 1, name: planted.courseName })).toBeVisible();
				await expect(page.getByTestId('park-course-safety')).toBeVisible();
				await expect(page.getByTestId('park-course-sign-in')).toBeVisible();
				await expect(page.getByTestId('park-board')).toHaveCount(0);
			} finally {
				await teardown(planted);
			}
		});

		test('a course over 15 km carries the long-course notice, and one at 15 km does not', async ({
			page,
		}) => {
			let long: Planted | null = null;
			let edge: Planted | null = null;
			try {
				long = await plantCourse({ baseLat: 38.0, lng: -80.0, lengthM: 21_100, checkpoints: [] });
				edge = await plantCourse({ baseLat: 38.3, lng: -80.1, lengthM: 15_000, checkpoints: [] });
				await page.goto(`/parks/us-va/${long.parkSlug}/lake-loop`);
				await expect(page.getByRole('heading', { level: 1, name: long.courseName })).toBeVisible();
				await expect(page.getByTestId('park-course-long')).toContainText(
					'Start early enough to finish before the park closes.',
				);
				await expect(page.getByTestId('park-course-not-affiliated')).toBeVisible();

				await page.goto(`/parks/us-va/${edge.parkSlug}/lake-loop`);
				await expect(page.getByRole('heading', { level: 1, name: edge.courseName })).toBeVisible();
				await expect(page.getByTestId('park-course-not-affiliated')).toBeVisible();
				await expect(page.getByTestId('park-course-long')).toHaveCount(0);
			} finally {
				await teardown(long);
				await teardown(edge);
			}
		});
	});
});
