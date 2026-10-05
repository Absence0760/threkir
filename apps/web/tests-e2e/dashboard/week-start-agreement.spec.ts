import { expect, test } from '@playwright/test';

import { browserDayAt, lastBrowserWeekday } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * The "This Week" tile and the mileage chart's current-week bar are the same
 * seven days, on either `week_start_day`.
 *
 * Field report: with week start set to Sunday the tile read 22.50 km "this
 * week" while the chart beside it read 7.50 km. The chart was fetched in the
 * same batch as the settings, so it was bucketed with the page's default
 * Monday before the preference arrived — on every cold load, which a fresh
 * browser context is. Both now take their window from `weekStartLocal`.
 *
 * The page clock is pinned to the most recent Saturday at 22:00 (browser
 * zone), so the seeded runs are fixed relative to the week and the seam is
 * exercised on both sides: a run at 23:30 the Saturday before and one at
 * 00:30 on the Sunday.
 */

const SATURDAY = lastBrowserWeekday(6);

// [days from the pinned Saturday, hour, minute, metres]
const RUNS = [
	[-7, 23, 30, 4_000], // previous Saturday, late
	[-6, 0, 30, 3_000], // Sunday, early
	[-5, 12, 0, 5_000], // Monday
	[0, 12, 0, 7_500], // Saturday
] as const;

async function setWeekStart(userId: string, day: 'monday' | 'sunday') {
	const { error } = await getAdminClient()
		.from('user_settings')
		.upsert({ user_id: userId, prefs: { week_start_day: day } }, { onConflict: 'user_id' });
	if (error) throw new Error(`setting week_start_day failed: ${error.message}`);
}

test.describe('/dashboard this-week tile vs mileage chart', () => {
	let runner: SagaUser;

	test.beforeAll(async () => {
		[runner] = await createSagaUsers(1, { displayNames: ['Week Start Runner'] });
		for (const [day, hour, minute, distance_m] of RUNS) {
			await insertRun({
				user_id: runner.id,
				started_at: browserDayAt(SATURDAY + day, hour, minute),
				duration_s: Math.round(distance_m * 0.33),
				distance_m,
				source: 'app',
			});
		}
	});

	test.afterAll(async () => {
		if (runner) await deleteSagaUsers([runner]);
	});

	for (const [weekStart, expected, barLabel] of [
		['sunday', '15.50 km', / · 15\.50 km$/],
		['monday', '12.50 km', / · 12\.50 km$/],
	] as const) {
		test(`agree when the week starts on ${weekStart}`, async ({ browser }) => {
			await setWeekStart(runner.id, weekStart);
			const ctx = await browser.newContext({ storageState: runner.storageStatePath });
			const page = await ctx.newPage();
			try {
				await page.clock.setFixedTime(browserDayAt(SATURDAY, 22));
				await page.goto('/dashboard');

				await expect(page.getByTestId('dash-this-week-distance')).toHaveText(expected, {
					timeout: 15_000,
				});
				const currentWeekBar = page.locator('.chart [role="listitem"]').last();
				await expect(currentWeekBar).toHaveAttribute('aria-label', barLabel);
			} finally {
				await ctx.close();
			}
		});
	}
});
