import { expect, test } from '../fixtures/test';
import type { Browser, BrowserContext } from '@playwright/test';
import { getAdminClient } from '../fixtures/local-supabase';
import { readRow, readRows } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * The NPS closures review queue (issue #1313 Phase 6): flags the daily sweep
 * recorded (here through the same service-role RPC the Edge Function calls)
 * wait at /admin/park-alerts; the reports queue says how many; an admin
 * closes the course from a flag with the note the course page shows, or
 * dismisses one; a flag never changes a course by itself; a runner is refused.
 */

const TAG = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
const PARK_SLUG = `e2e-nps-park-${TAG}`;
const COURSES = [
	{ slug: 'meadow-loop', name: `Meadow Loop ${TAG}` },
	{ slug: 'ridge-trail', name: `Ridge Trail ${TAG}` },
] as const;
const CLOSE_NOTE = `Closed by the park for a prescribed fire ${TAG}.`;

let parkId: string | null = null;
const segmentIds: string[] = [];
const courseIds: string[] = [];

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
			name: `E2E National Park ${TAG}`,
			agency: 'nps',
			nps_park_code: 'zzzz',
			region_code: 'US-VA',
			country_code: 'US',
			timezone: 'America/New_York',
		})
		.select('id')
		.single();
	if (park.error) throw park.error;
	parkId = park.data.id;
	for (const [i, c] of COURSES.entries()) {
		const seg = await admin
			.from('global_segments')
			.insert({
				name: c.name,
				waypoints: [
					{ lat: 38.5, lng: -78.4 + i * 0.01 },
					{ lat: 38.509, lng: -78.4 + i * 0.01 },
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
			.insert({ park_id: parkId, global_segment_id: seg.data.id, slug: c.slug, course_shape: 'loop', geometry_source: 'nps' })
			.select('id')
			.single();
		if (course.error) throw course.error;
		courseIds.push(course.data.id);
	}
	const flag = (courseId: string, alertId: string, title: string) => ({
		course_id: courseId,
		alert_id: alertId,
		category: 'Park Closure',
		title,
		description: 'Closed until further notice.',
		url: 'https://www.nps.gov/zzzz/planyourvisit/conditions.htm',
		match: 'named',
	});
	const { error } = await admin.rpc('record_park_nps_alerts', {
		p_park_id: parkId,
		p_flags: [
			flag(courseIds[0], `FIRE-${TAG}`, `Prescribed fire at the meadow ${TAG}`),
			flag(courseIds[1], `SLIDE-${TAG}`, `Rock slide on the ridge ${TAG}`),
		],
		p_seen_alert_ids: [`FIRE-${TAG}`, `SLIDE-${TAG}`],
	});
	if (error) throw error;
});

test.afterAll(async () => {
	const admin = getAdminClient();
	if (parkId) await admin.from('parks').delete().eq('id', parkId);
	if (segmentIds.length) await admin.from('global_segments').delete().in('id', segmentIds);
});

test.describe.serial('NPS park alerts review', () => {
	let users: SagaUser[] = [];

	test.beforeAll(async () => {
		users = await createSagaUsers(2, { displayNames: ['Saga NPS Runner', 'Saga NPS Moderator'] });
		await getAdminClient().from('app_admins').upsert({ user_id: users[1].id }, { onConflict: 'user_id' });
	});

	test.afterAll(async () => {
		if (users.length) {
			await getAdminClient().from('app_admins').delete().eq('user_id', users[1].id);
			await deleteSagaUsers(users);
		}
	});

	test('a runner is refused the queue', async ({ browser }) => {
		const ctx = await signedInContext(browser, users[0]);
		try {
			const page = await ctx.newPage();
			await page.goto('/admin/park-alerts');
			await expect(page.getByTestId('park-alerts-not-authorized')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('park-alert-row')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});

	test('the reports queue links to the flags waiting, and a flag leaves its course open', async ({ browser }) => {
		const course = await readRow(
			'the flagged course',
			getAdminClient().from('park_courses').select('status').eq('id', courseIds[0]).single(),
		);
		expect(course).toEqual({ status: 'open' });
		const ctx = await signedInContext(browser, users[1]);
		try {
			const page = await ctx.newPage();
			await page.goto('/admin/reports');
			const link = page.getByTestId('admin-park-alerts-link');
			await expect(link).toContainText('NPS park alerts to review:', { timeout: 15_000 });
			await link.click();
			await expect(page).toHaveURL(/\/admin\/park-alerts$/);
			const row = page.getByTestId('park-alert-row').filter({ hasText: `Prescribed fire at the meadow ${TAG}` });
			await expect(row).toBeVisible({ timeout: 15_000 });
			await expect(row).toContainText(COURSES[0].name);
			await expect(row).toContainText('Park Closure');
			await expect(row).toContainText('The alert names this course');
			await expect(row.getByRole('link', { name: 'Read on nps.gov' })).toHaveAttribute(
				'href',
				'https://www.nps.gov/zzzz/planyourvisit/conditions.htm',
			);
		} finally {
			await ctx.close();
		}
	});

	test('the admin closes a course from its flag, with the note the course page shows', async ({ browser }) => {
		const ctx = await signedInContext(browser, users[1]);
		try {
			const page = await ctx.newPage();
			await page.goto('/admin/park-alerts');
			const row = page.getByTestId('park-alert-row').filter({ hasText: `Prescribed fire at the meadow ${TAG}` });
			await expect(row).toBeVisible({ timeout: 15_000 });
			await row.getByTestId('park-alert-close').click();
			const dialog = page.getByTestId('park-alert-close-dialog');
			await dialog.getByTestId('park-alert-close-confirm').click();
			await expect(dialog.getByRole('alert')).toContainText('Write the note the course page shows.');
			await dialog.getByTestId('park-alert-close-note').fill(CLOSE_NOTE);
			await dialog.getByTestId('park-alert-close-confirm').click();
			await expect(page.getByText('Course closed.')).toBeVisible({ timeout: 10_000 });
			await expect(row).toHaveCount(0);

			const course = await readRow(
				'the closed course',
				getAdminClient().from('park_courses').select('status, status_note').eq('id', courseIds[0]).single(),
			);
			expect(course).toEqual({ status: 'closed', status_note: CLOSE_NOTE });
			const flags = await readRows(
				'the closed course\'s flags',
				getAdminClient().from('park_course_nps_alerts').select('review_status').eq('park_course_id', courseIds[0]),
			);
			expect(flags).toEqual([{ review_status: 'reviewed' }]);

			await page.getByTestId('park-alerts-tab-reviewed').click();
			await expect(
				page.getByTestId('park-alert-row').filter({ hasText: `Prescribed fire at the meadow ${TAG}` }),
			).toContainText('This course is already closed.');
		} finally {
			await ctx.close();
		}
	});

	test('the admin dismisses a flag, which leaves the course open', async ({ browser }) => {
		const ctx = await signedInContext(browser, users[1]);
		try {
			const page = await ctx.newPage();
			await page.goto('/admin/park-alerts');
			const row = page.getByTestId('park-alert-row').filter({ hasText: `Rock slide on the ridge ${TAG}` });
			await expect(row).toBeVisible({ timeout: 15_000 });
			await row.getByTestId('park-alert-dismiss').click();
			await expect(page.getByText('Alert filed.')).toBeVisible({ timeout: 10_000 });
			await expect(row).toHaveCount(0);
			await page.getByTestId('park-alerts-tab-dismissed').click();
			await expect(page.getByTestId('park-alert-row').filter({ hasText: `Rock slide on the ridge ${TAG}` })).toBeVisible();
			const course = await readRow(
				'the dismissed flag\'s course',
				getAdminClient().from('park_courses').select('status').eq('id', courseIds[1]).single(),
			);
			expect(course).toEqual({ status: 'open' });
		} finally {
			await ctx.close();
		}
	});
});
