import { expect, test } from '../fixtures/test';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';
import type { TrackPoint } from '../../src/lib/types';

/**
 * Run detail's park course chips (issue #1313, months #1343): the owner sees a
 * chip per park course the run completed, with the time and its places on
 * that month's and that season's fastest boards, linking to the course page
 * on the effort's month. A failed read is a quiet line
 * with Retry, never a broken page, and nobody else sees the chips.
 */

const TRACK: TrackPoint[] = Array.from({ length: 8 }, (_, i) => ({
	lat: -37.7 + i * 0.001,
	lng: 144.86 + (i % 2) * 0.0008,
	ele: 20 + i * 4,
	ts: new Date(Date.UTC(2026, 4, 12, 8, i)).toISOString(),
}));

test.describe('run detail park course chips', () => {
	let runId: string;
	let parkId: string;
	let segmentId: string;
	let parkSlug: string;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		const tag = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: '2026-05-12T08:00:00Z',
			distance_m: 5_000,
			duration_s: 1_500,
			metadata: { title: 'Park chip run' },
			track: TRACK,
		});
		// The course runs through the midpoints of the track's chords, so its
		// derived start and end lines sit mid-chord and the run crosses both;
		// run detail's own scorer times it during the view.
		const mid = (a: TrackPoint, b: TrackPoint) => ({ lat: (a.lat + b.lat) / 2, lng: (a.lng + b.lng) / 2 });
		const { data: seg, error: segErr } = await admin
			.from('global_segments')
			.insert({
				name: `E2E Chip Loop ${tag}`,
				waypoints: TRACK.slice(1).map((p, i) => mid(TRACK[i], p)),
				distance_m: 790,
				surface: 'trail',
				country_code: 'US',
			})
			.select('id')
			.single();
		if (segErr) throw segErr;
		segmentId = seg.id;
		parkSlug = `e2e-chip-${tag}`;
		const { data: park, error: parkErr } = await admin
			.from('parks')
			.insert({
				slug: parkSlug,
				name: `E2E Chip Park ${tag}`,
				agency: 'state',
				region_code: 'US-VA',
				country_code: 'US',
				timezone: 'America/New_York',
			})
			.select('id')
			.single();
		if (parkErr) throw parkErr;
		parkId = park.id;
		const { error: courseErr } = await admin.from('park_courses').insert({
			park_id: parkId,
			global_segment_id: segmentId,
			slug: 'chip-loop',
			course_shape: 'loop',
			geometry_source: 'osm',
		});
		if (courseErr) throw courseErr;
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		await deleteRun(runId);
		await admin.from('parks').delete().eq('id', parkId).then(() => {}, () => {});
		await admin.from('global_segments').delete().eq('id', segmentId).then(() => {}, () => {});
	});

	test.describe('as the owner', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('a completed course shows its time and its month and season places, linking to the month board', async ({ page }) => {
			await page.goto(`/runs/${runId}`);
			const chips = page.getByTestId('run-park-courses');
			await expect(chips).toBeVisible({ timeout: 20_000 });
			await expect(chips).toHaveAttribute('aria-label', 'Park courses on this run');
			const chip = chips.getByTestId('run-park-course-chip');
			await expect(chip).toHaveCount(1);
			await expect(chip).toContainText('E2E Chip Loop');
			await expect(chip).toContainText('6:00');
			// 12 May 2026 08:00 UTC is May in New York too.
			await expect(chip).toContainText('#1 in May, #1 in 2026');
			await expect(chip).toHaveAttribute('href', `/parks/us-va/${parkSlug}/chip-loop?period=2026-05`);
		});

		test('a failed read is a quiet line with Retry, and the page stands', async ({ page, mockRoute }) => {
			let fail = true;
			await mockRoute(page, '**/rest/v1/rpc/run_park_course_times*', (route) =>
				fail
					? route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' })
					: route.fallback(),
			);
			await page.goto(`/runs/${runId}`);
			const error = page.getByTestId('run-park-courses-error');
			await expect(error).toContainText("Couldn't load your park course times.", { timeout: 20_000 });
			await expect(page.getByRole('heading', { name: 'Segments' })).toBeVisible();
			await expect(page.getByTestId('run-park-courses')).toHaveCount(0);

			fail = false;
			await error.getByRole('button', { name: 'Retry' }).click();
			await expect(page.getByTestId('run-park-course-chip')).toContainText('#1 in 2026', { timeout: 20_000 });
			await expect(error).toHaveCount(0);
		});

		test('a run with no park course shows no chips', async ({ page }) => {
			const admin = getAdminClient();
			await admin.from('park_courses').delete().eq('park_id', parkId);
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { name: 'Segments' })).toBeVisible({ timeout: 20_000 });
			await expect(page.getByTestId('run-park-courses')).toHaveCount(0);
			await expect(page.getByTestId('run-park-courses-error')).toHaveCount(0);
		});
	});

	test.describe('as someone else', () => {
		test.use({ storageState: USER_B.storageStatePath });

		test('the chips are the owner\'s alone, and are never asked for', async ({ page, mockRoute }) => {
			const admin = getAdminClient();
			await admin.from('runs').update({ is_public: true }).eq('id', runId);
			await mockRoute(page, '**/rest/v1/rpc/run_park_course_times*', (route) => route.fallback(), {
				neverFires: 'only the run owner asks for their park course times',
			});
			await page.goto(`/runs/${runId}`);
			await expect(page.getByRole('heading', { name: 'Park chip run' })).toBeVisible({ timeout: 20_000 });
			await expect(page.getByText('0 comments')).toBeVisible();
			await expect(page.getByTestId('run-park-courses')).toHaveCount(0);
		});
	});
});
