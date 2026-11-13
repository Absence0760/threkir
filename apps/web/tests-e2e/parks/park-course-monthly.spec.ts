import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun, deleteRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Monthly park course boards (issue #1343, decisions § 2511): the course
 * page's This month / This year / All time control with month arrows and
 * `?period=YYYY-MM` in the address, a deep link straight onto a month, the
 * park page's runners this month, and the month-close notice in the bell,
 * which names the course, the month and the best time and opens that
 * month's board.
 *
 * Months are the park's (America/New_York). Every time is planted at 16:00
 * UTC on the 15th, or now, so no case sits near a New York midnight. Rows are
 * planted (service role) under a unique slug and removed afterwards.
 */

const TZ = 'America/New_York';
const tag = () => `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

/** The park's year and month at `at`, read as the server reads them. */
function parkMonth(at: Date): { year: number; month: number } {
	const parts = new Intl.DateTimeFormat('en-US', { timeZone: TZ, year: 'numeric', month: 'numeric' }).formatToParts(at);
	return {
		year: Number(parts.find((p) => p.type === 'year')!.value),
		month: Number(parts.find((p) => p.type === 'month')!.value),
	};
}

function period(m: { year: number; month: number }): string {
	return `${m.year}-${String(m.month).padStart(2, '0')}`;
}

function label(m: { year: number; month: number }): string {
	return new Intl.DateTimeFormat('en', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(
		new Date(Date.UTC(m.year, m.month - 1, 15)),
	);
}

interface Planted {
	parkId: string;
	parkSlug: string;
	courseId: string;
	courseName: string;
	segmentId: string;
	runIds: string[];
}

async function plant(): Promise<Planted> {
	const admin = getAdminClient();
	const t = tag();
	const courseName = `E2E Month Loop ${t}`;
	const { data: seg, error: segErr } = await admin
		.from('global_segments')
		.insert({
			name: courseName,
			waypoints: [
				{ lat: 37.31, lng: -78.71 },
				{ lat: 37.319, lng: -78.71 },
			],
			distance_m: 1000,
			surface: 'trail',
			country_code: 'US',
		})
		.select('id')
		.single();
	if (segErr) throw segErr;
	const parkSlug = `e2e-month-park-${t}`;
	const { data: park, error: parkErr } = await admin
		.from('parks')
		.insert({
			slug: parkSlug,
			name: `E2E Month State Park ${t}`,
			agency: 'state',
			region_code: 'US-VA',
			country_code: 'US',
			timezone: TZ,
		})
		.select('id')
		.single();
	if (parkErr) throw parkErr;
	const { data: course, error: courseErr } = await admin
		.from('park_courses')
		.insert({
			park_id: park.id,
			global_segment_id: seg.id,
			slug: 'month-loop',
			course_shape: 'out_and_back',
			geometry_source: 'osm',
		})
		.select('id')
		.single();
	if (courseErr) throw courseErr;
	return { parkId: park.id, parkSlug, courseId: course.id, courseName, segmentId: seg.id, runIds: [] };
}

async function effort(p: Planted, userId: string, timeS: number, at: Date) {
	const runId = await insertRun({
		user_id: userId,
		started_at: at.toISOString(),
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
		started_at: at.toISOString(),
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

const now = new Date();
const thisMonth = parkMonth(now);
const lastMonth = thisMonth.month === 1 ? { year: thisMonth.year - 1, month: 12 } : { year: thisMonth.year, month: thisMonth.month - 1 };
const lastMonthMid = new Date(Date.UTC(lastMonth.year, lastMonth.month - 1, 15, 16));

test.describe('monthly park course boards', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let planted: Planted | null = null;
	test.beforeEach(async () => {
		planted = await plant();
		// This month: A 10:00, B 11:40. Last month: A 8:20, B 9:10.
		await effort(planted, USER_A.id, 600, now);
		await effort(planted, USER_B.id, 700, now);
		await effort(planted, USER_A.id, 500, lastMonthMid);
		await effort(planted, USER_B.id, 550, lastMonthMid);
	});
	test.afterEach(async () => {
		await teardown(planted);
		planted = null;
	});

	test('This month narrows the board to the park\'s month, the arrows step back, and the address follows', async ({ page }) => {
		const p = planted!;
		const base = `/parks/us-va/${p.parkSlug}/month-loop`;
		await page.goto(base);
		await expect(page.getByTestId('park-season-this-year')).toHaveAttribute('aria-pressed', 'true');
		await expect(page.getByTestId('park-period-month-nav')).toHaveCount(0);

		await page.getByTestId('park-period-this-month').click();
		await expect(page).toHaveURL(new RegExp(`${base}\\?period=${period(thisMonth)}$`));
		await expect(page.getByTestId('park-period-this-month')).toHaveAttribute('aria-pressed', 'true');
		await expect(page.getByTestId('park-period-month')).toHaveText(label(thisMonth));
		await expect(page.getByTestId('park-period-next')).toBeDisabled();
		const rows = page.getByTestId('park-board').locator('li');
		await expect(rows).toHaveCount(2);
		await expect(rows.nth(0).locator('.value')).toHaveText('10:00');
		await expect(rows.nth(0)).toHaveClass(/viewer/);
		await expect(rows.nth(1).locator('.value')).toHaveText('11:40');

		await page.getByTestId('park-period-prev').click();
		await expect(page).toHaveURL(new RegExp(`${base}\\?period=${period(lastMonth)}$`));
		await expect(page.getByTestId('park-period-month')).toHaveText(label(lastMonth));
		await expect(page.getByTestId('park-period-next')).toBeEnabled();
		await expect(rows.nth(0).locator('.value')).toHaveText('8:20');
		await expect(rows.nth(1).locator('.value')).toHaveText('9:10');

		await page.getByTestId('park-board-completions').click();
		await expect(rows).toHaveCount(2);
		await expect(rows.nth(0).locator('.value')).toHaveText('1 day');

		await page.getByTestId('park-season-all-time').click();
		await expect(page).toHaveURL(new RegExp(`${base}\\?period=all$`));
		await expect(page.getByTestId('park-period-month-nav')).toHaveCount(0);
		await expect(rows.nth(0).locator('.value')).toHaveText('2 days');

		await page.getByTestId('park-season-this-year').click();
		await expect(page).toHaveURL(new RegExp(`${base}$`));
	});

	test('a ?period= link opens straight on that month, and a month still to come opens this year', async ({ page }) => {
		const p = planted!;
		const base = `/parks/us-va/${p.parkSlug}/month-loop`;
		await page.goto(`${base}?period=${period(lastMonth)}`);
		await expect(page.getByTestId('park-period-this-month')).toHaveAttribute('aria-pressed', 'true');
		await expect(page.getByTestId('park-period-month')).toHaveText(label(lastMonth));
		await expect(page.getByTestId('park-board').locator('li').nth(0).locator('.value')).toHaveText('8:20');

		await page.goto(`${base}?period=${thisMonth.year + 1}-01`);
		await expect(page.getByTestId('park-season-this-year')).toHaveAttribute('aria-pressed', 'true');
		await expect(page.getByTestId('park-period-month-nav')).toHaveCount(0);
	});

	test('the park page says how many ran each course this month', async ({ page }) => {
		const p = planted!;
		await page.goto(`/parks/us-va/${p.parkSlug}`);
		const card = page.getByTestId('park-course-card').filter({ hasText: p.courseName });
		await expect(card.getByTestId('park-course-month-runners')).toContainText('2 runners this month');
	});

	test('a failed runner count is said with a retry, and the courses stand', async ({ page, mockRoute }) => {
		const p = planted!;
		let fail = true;
		await mockRoute(page, '**/rest/v1/rpc/park_course_month_runners*', (route) =>
			fail
				? route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' })
				: route.fallback(),
		);
		await page.goto(`/parks/us-va/${p.parkSlug}`);
		const failed = page.getByTestId('park-month-runners-failed');
		await expect(failed).toContainText("Couldn't load how many ran each course this month.");
		await expect(page.getByTestId('park-course-card')).toHaveCount(1);
		fail = false;
		await failed.getByRole('button', { name: 'Retry' }).click();
		await expect(page.getByTestId('park-course-month-runners')).toContainText('2 runners this month');
		await expect(failed).toHaveCount(0);
	});

	test('the month-close notice names the course, the month and the best time, and opens that month', async ({ page }) => {
		const p = planted!;
		const admin = getAdminClient();
		// Only this row is planted and removed: other specs count USER_A's
		// notifications, so none of theirs is cleared here.
		const { data: notice, error } = await admin
			.from('notifications')
			.insert({
				user_id: USER_A.id,
				kind: 'park_course_month_closed',
				park_course_id: p.courseId,
				park_course_month: `${period(lastMonth)}-01`,
				park_course_time_s: 500,
			})
			.select('id')
			.single();
		if (error) throw error;
		try {
			await page.goto('/dashboard');
			await page.locator('.bell-wrap .bell-btn').click();
			const popover = page.locator('.bell-wrap [role="dialog"]');
			const item = popover.getByRole('button', { name: new RegExp(p.courseName) });
			await expect(item).toContainText(`${p.courseName}: the ${label(lastMonth)} board has closed. Your best: 8:20`);
			await expect(item).not.toContainText('#');
			await item.click();
			await expect(page).toHaveURL(new RegExp(`/parks/us-va/${p.parkSlug}/month-loop\\?period=${period(lastMonth)}$`));
			await expect(page.getByTestId('park-period-month')).toHaveText(label(lastMonth));
		} finally {
			await admin.from('notifications').delete().eq('id', notice.id).then(() => {}, () => {});
		}
	});
});

test.describe('monthly park course boards, signed out', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('the park page asks for no runner counts', async ({ page, mockRoute }) => {
		let planted: Planted | null = null;
		try {
			planted = await plant();
			await mockRoute(page, '**/rest/v1/rpc/park_course_month_runners*', (route) => route.fallback(), {
				neverFires: 'the runner counts need an account, like the boards',
			});
			await page.goto(`/parks/us-va/${planted.parkSlug}`);
			await expect(page.getByTestId('park-course-card')).toHaveCount(1);
			await expect(page.getByTestId('park-course-month-runners')).toHaveCount(0);
		} finally {
			await teardown(planted);
		}
	});
});
