import { expect, test } from '../fixtures/test';
import type { Browser, BrowserContext } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { readRow, readRows } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * "Report a problem with this course" (issue #1346, migrations
 * 20271213000001..5, decisions § 2449).
 *
 * The filing RPC's validation, caps and grants are pinned by
 * park_course_reports_test.sql and the Edge Function's order of checks by
 * park-course-report/handler.test.ts. This spec walks the pages on top:
 *
 *   a signed-out land manager asks for a course to come down from the course
 *   page, with a contact email, and the course stays open; a signed-in runner
 *   reports a hazard on another course as themselves; a site admin sees the
 *   land-manager request in /admin/reports with its deadline, closes the
 *   course with a note, and the course page then shows it closed with that
 *   note.
 *
 * Two courses are planted (service role) in one park under a unique slug, at
 * (37.6, -78.6), which no seed row or other spec uses, and removed afterwards
 * with the reports filed on them.
 */

const M_PER_DEG_LAT = 111_320;
const BASE_LAT = 37.6;
const LNG = -78.6;
const TAG = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
const PARK_SLUG = `e2e-report-park-${TAG}`;
const COURSES = [
	{ slug: 'lake-loop', name: `Lake Loop ${TAG}` },
	{ slug: 'ridge-loop', name: `Ridge Loop ${TAG}` },
] as const;
const CLOSE_NOTE = `Closed at the park's request for trail restoration ${TAG}.`;

let parkId: string | null = null;
const segmentIds: string[] = [];
const courseIds: string[] = [];

async function anonymousContext(browser: Browser): Promise<BrowserContext> {
	const ctx = await browser.newContext({ storageState: { cookies: [], origins: [] } });
	await acceptCookieConsent(ctx);
	return ctx;
}

async function signedInContext(browser: Browser, user: SagaUser): Promise<BrowserContext> {
	const ctx = await browser.newContext({ storageState: user.storageStatePath });
	await acceptCookieConsent(ctx);
	return ctx;
}

test.beforeAll(async () => {
	const admin = getAdminClient();
	const park = await admin
		.from('parks')
		.insert({
			slug: PARK_SLUG,
			name: `E2E Report State Park ${TAG}`,
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
					{ lat: BASE_LAT, lng },
					{ lat: BASE_LAT + 1000 / M_PER_DEG_LAT, lng },
				],
				distance_m: 1000,
				surface: 'trail',
				country_code: 'US',
			})
			.select('id')
			.single();
		if (seg.error) throw seg.error;
		segmentIds.push(seg.data.id);
		const course = await admin
			.from('park_courses')
			.insert({ park_id: parkId, global_segment_id: seg.data.id, slug: c.slug, course_shape: 'loop', geometry_source: 'osm' })
			.select('id')
			.single();
		if (course.error) throw course.error;
		courseIds.push(course.data.id);
	}
});

test.afterAll(async () => {
	const admin = getAdminClient();
	if (courseIds.length) await admin.from('reports').delete().eq('target_kind', 'park_course').in('target_id', courseIds);
	if (parkId) await admin.from('parks').delete().eq('id', parkId);
	if (segmentIds.length) await admin.from('global_segments').delete().in('id', segmentIds);
});

test.describe.serial('report a problem with a park course', () => {
	let users: SagaUser[] = [];

	test.beforeAll(async () => {
		users = await createSagaUsers(2, { displayNames: ['Saga Course Runner', 'Saga Course Moderator'] });
		await getAdminClient().from('app_admins').upsert({ user_id: users[1].id }, { onConflict: 'user_id' });
	});

	test.afterAll(async () => {
		if (users.length) {
			await getAdminClient().from('app_admins').delete().eq('user_id', users[1].id);
			await deleteSagaUsers(users);
		}
	});

	test('a signed-out land manager asks for the course to come down, and it stays open', async ({ browser }) => {
		const ctx = await anonymousContext(browser);
		try {
			const page = await ctx.newPage();
			await page.goto(`/parks/us-va/${PARK_SLUG}/${COURSES[0].slug}`);
			const open = page.getByTestId('park-course-report');
			await expect(open).toBeVisible({ timeout: 15_000 });
			// It sits with the notices, not beside the primary action.
			await expect(page.getByTestId('park-course-notices').locator('..').getByTestId('park-course-report')).toBeVisible();
			await open.click();

			const dialog = page.getByTestId('park-course-report-dialog');
			await expect(dialog).toBeVisible();
			await dialog.getByTestId('park-course-report-reason-land_manager_request').check();
			await dialog.getByTestId('park-course-report-email').fill('not an email');
			await dialog.getByTestId('park-course-report-notes').fill('Please take this course down: the trail is closed for restoration.');
			await expect(dialog.getByTestId('park-course-report-submit')).toBeDisabled();
			await dialog.getByTestId('park-course-report-email').fill('ranger@e2e-park.example');
			await dialog.getByTestId('park-course-report-submit').click();
			await expect(page.getByText('Thanks. Your report is with the Threkir team.')).toBeVisible({ timeout: 10_000 });
		} finally {
			await ctx.close();
		}

		const admin = getAdminClient();
		const rows = await readRows(
			'the signed-out report',
			admin
				.from('reports')
				.select('reporter_id, signed_out, reason, contact_email, status')
				.eq('target_kind', 'park_course')
				.eq('target_id', courseIds[0]),
		);
		expect(rows).toEqual([
			{
				reporter_id: null,
				signed_out: true,
				reason: 'land_manager_request',
				contact_email: 'ranger@e2e-park.example',
				status: 'pending',
			},
		]);
		const course = await readRow(
			'the reported course',
			admin.from('park_courses').select('status').eq('id', courseIds[0]).single(),
		);
		expect(course.status).toBe('open');
	});

	test('a signed-in runner reports a hazard as themselves', async ({ browser }) => {
		const runner = users[0];
		const ctx = await signedInContext(browser, runner);
		try {
			const page = await ctx.newPage();
			await page.goto(`/parks/us-va/${PARK_SLUG}/${COURSES[1].slug}`);
			await page.getByTestId('park-course-report').click();
			const dialog = page.getByTestId('park-course-report-dialog');
			await dialog.getByTestId('park-course-report-reason-course_hazard').check();
			await dialog.getByTestId('park-course-report-notes').fill('A tree is down across the trail at the second bridge.');
			await dialog.getByTestId('park-course-report-submit').click();
			await expect(page.getByText('Thanks. Your report is with the Threkir team.')).toBeVisible({ timeout: 10_000 });

			// A second report from the same runner while the first is open is refused.
			await page.getByTestId('park-course-report').click();
			await dialog.getByTestId('park-course-report-notes').fill('Still down.');
			await dialog.getByTestId('park-course-report-submit').click();
			await expect(dialog.getByTestId('park-course-report-error')).toHaveText(
				"You've already reported this course, and that report is still open.",
			);
		} finally {
			await ctx.close();
		}

		const rows = await readRows(
			'the signed-in report',
			getAdminClient()
				.from('reports')
				.select('reporter_id, signed_out, reason')
				.eq('target_kind', 'park_course')
				.eq('target_id', courseIds[1]),
		);
		expect(rows).toEqual([{ reporter_id: runner.id, signed_out: false, reason: 'course_hazard' }]);
	});

	test('the admin closes the course from the land-manager request', async ({ browser }) => {
		const ctx = await signedInContext(browser, users[1]);
		try {
			const page = await ctx.newPage();
			await page.goto('/admin/reports');
			const row = page.getByTestId('admin-queue-row').filter({ hasText: courseIds[0].slice(0, 8) });
			await expect(row).toBeVisible({ timeout: 15_000 });
			await expect(row.getByTestId('admin-land-manager-row')).toContainText('Land-manager request');
			await expect(row.getByTestId('admin-land-manager-due')).toContainText('Close by');
			await row.getByTestId('admin-queue-review').click();

			const panel = page.getByTestId('admin-course-panel');
			await expect(panel).toContainText(COURSES[0].name);
			await expect(page.getByTestId('admin-report-contact')).toContainText('ranger@e2e-park.example');
			await expect(page.getByText('Not signed in')).toBeVisible();
			await expect(panel.getByTestId('admin-course-close')).toBeDisabled();
			await panel.getByTestId('admin-course-note').fill(CLOSE_NOTE);
			await panel.getByTestId('admin-course-close').click();
			await page.getByTestId('admin-course-confirm').getByRole('button', { name: 'Close course' }).click();
			await expect(page.getByText('Course closed.')).toBeVisible({ timeout: 10_000 });
			await expect(panel.getByTestId('admin-course-status')).toContainText(CLOSE_NOTE);
			await expect(panel.getByTestId('admin-course-history')).toContainText('Closed');

			const course = await readRow(
				'the closed course',
				getAdminClient().from('park_courses').select('status, status_note').eq('id', courseIds[0]).single(),
			);
			expect(course).toEqual({ status: 'closed', status_note: CLOSE_NOTE });
			const pending = await readRows(
				'pending reports left on the closed course',
				getAdminClient()
					.from('reports')
					.select('id')
					.eq('target_kind', 'park_course')
					.eq('target_id', courseIds[0])
					.eq('status', 'pending'),
			);
			expect(pending).toEqual([]);

			await page.goto(`/parks/us-va/${PARK_SLUG}/${COURSES[0].slug}`);
			await expect(page.getByTestId('park-course-closed')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByText(CLOSE_NOTE)).toBeVisible();
			await expect(page.getByTestId('park-course-navigate')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
