import { expect, test } from '../fixtures/test';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';
import type { TrackPoint } from '../../src/lib/types';

/**
 * Run detail's park course attempts (issue #1446): when a run started a park
 * course and got no time, its owner sees one card for that course saying which
 * rule it missed, with a bar of how far along it got, linking to the course. A
 * failed read leaves the cards out and the page stands; nobody else sees them.
 *
 * The run is in Melbourne and the course in Virginia, so run detail's own
 * scorer finds nothing near the track to re-score, and the seeded attempt is
 * the one the page reads.
 */

const TRACK: TrackPoint[] = Array.from({ length: 8 }, (_, i) => ({
	lat: -37.7 + i * 0.001,
	lng: 144.86 + (i % 2) * 0.0008,
	ele: 20,
	ts: new Date(Date.UTC(2026, 4, 12, 8, i)).toISOString(),
}));

const ATTEMPTS_RPC = '**/rest/v1/rpc/get_run_park_course_attempts*';

test.describe('run detail park course attempts', () => {
	let runId: string;
	let parkId: string;
	let segmentId: string;
	let parkCourseId: string;
	let parkSlug: string;
	let courseName: string;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		const tag = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: '2026-05-12T08:00:00Z',
			distance_m: 3_200,
			duration_s: 1_100,
			metadata: { title: 'Park attempt run' },
			track: TRACK,
		});
		courseName = `E2E Attempt Loop ${tag}`;
		const { data: seg, error: segErr } = await admin
			.from('global_segments')
			.insert({
				name: courseName,
				waypoints: [
					{ lat: 37.38, lng: -77.58 },
					{ lat: 37.39, lng: -77.57 },
					{ lat: 37.4, lng: -77.58 },
				],
				distance_m: 5_000,
				surface: 'trail',
				country_code: 'US',
			})
			.select('id')
			.single();
		if (segErr) throw segErr;
		segmentId = seg.id;
		parkSlug = `e2e-attempt-${tag}`;
		const { data: park, error: parkErr } = await admin
			.from('parks')
			.insert({
				slug: parkSlug,
				name: `E2E Attempt Park ${tag}`,
				agency: 'state',
				region_code: 'US-VA',
				country_code: 'US',
				timezone: 'America/New_York',
			})
			.select('id')
			.single();
		if (parkErr) throw parkErr;
		parkId = park.id;
		const { data: course, error: courseErr } = await admin
			.from('park_courses')
			.insert({
				park_id: parkId,
				global_segment_id: segmentId,
				slug: 'attempt-loop',
				course_shape: 'loop',
				geometry_source: 'osm',
			})
			.select('id')
			.single();
		if (courseErr) throw courseErr;
		parkCourseId = course.id;
		const { error: attemptErr } = await admin.from('park_course_attempts').insert({
			run_id: runId,
			user_id: USER_A.id,
			park_course_id: parkCourseId,
			outcome: 'stopped_short',
			progress_m: 3_200,
			course_m: 5_000,
			missed_checkpoint: null,
			checkpoint_count: 3,
			matcher_version: 4,
		});
		if (attemptErr) throw attemptErr;
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		await deleteRun(runId);
		await admin.from('parks').delete().eq('id', parkId).then(() => {}, () => {});
		await admin.from('global_segments').delete().eq('id', segmentId).then(() => {}, () => {});
	});

	test.describe('as the owner', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('a course started and not finished says how far the run got and to run the whole course', async ({ page }) => {
			await page.goto(`/runs/${runId}`);
			const section = page.getByTestId('run-park-course-attempts');
			await expect(section).toBeVisible({ timeout: 20_000 });
			await expect(section.getByRole('heading', { name: 'Park courses with no time' })).toBeVisible();
			const card = section.getByTestId('run-park-course-attempt');
			await expect(card).toHaveCount(1);
			await expect(card).toContainText(
				`${courseName}: no time. You ran 3.20 km of 5.00 km. Run the whole course to get a time.`,
			);
			await expect(card).toHaveAttribute('href', `/parks/us-va/${parkSlug}/attempt-loop`);
			const bar = card.getByRole('progressbar', { name: `How far you got on ${courseName}` });
			await expect(bar).toHaveAttribute('aria-valuenow', '64');
			await expect(bar).toHaveAttribute('aria-valuetext', '3.20 km of 5.00 km');
		});

		test('a skipped checkpoint names which one, and the reason is words', async ({ page }) => {
			const admin = getAdminClient();
			await admin
				.from('park_course_attempts')
				.update({ outcome: 'skipped_checkpoint', missed_checkpoint: 2, progress_m: 1_800 })
				.eq('run_id', runId);
			await page.goto(`/runs/${runId}`);
			const card = page.getByTestId('run-park-course-attempt');
			await expect(card).toContainText(
				`${courseName}: no time. You missed checkpoint 2 of 3. Stay on the course line to pass every one.`,
				{ timeout: 20_000 },
			);
			await expect(card.getByRole('progressbar')).toHaveAttribute('aria-valuetext', '1.80 km of 5.00 km');
		});

		test('a failed read leaves the cards out, and the page stands', async ({ page, mockRoute }) => {
			await mockRoute(page, ATTEMPTS_RPC, (route) =>
				route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' }),
			);
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { name: 'Segments' })).toBeVisible({ timeout: 20_000 });
			await expect(page.getByTestId('run-park-course-attempts')).toHaveCount(0);
		});

		test('a run with no attempt shows no cards', async ({ page }) => {
			const admin = getAdminClient();
			await admin.from('park_course_attempts').delete().eq('run_id', runId);
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { name: 'Segments' })).toBeVisible({ timeout: 20_000 });
			await expect(page.getByTestId('run-park-course-attempts')).toHaveCount(0);
		});
	});

	test.describe('as someone else', () => {
		test.use({ storageState: USER_B.storageStatePath });

		test("the cards are the owner's alone, and are never asked for", async ({ page, mockRoute }) => {
			const admin = getAdminClient();
			await admin.from('runs').update({ is_public: true }).eq('id', runId);
			await mockRoute(page, ATTEMPTS_RPC, (route) => route.fallback(), {
				neverFires: 'only the run owner asks why their park courses got no time',
			});
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { name: 'Park attempt run' })).toBeVisible({ timeout: 20_000 });
			await expect(page.getByText('0 comments')).toBeVisible();
			await expect(page.getByTestId('run-park-course-attempts')).toHaveCount(0);
		});
	});
});
