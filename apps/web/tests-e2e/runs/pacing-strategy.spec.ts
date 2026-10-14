import type { Page } from '@playwright/test';

import { browserDayAt } from '../fixtures/dates';
import { expect, test, type MockRoute } from '../fixtures/mock-route';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — the pacing-strategy review (decisions § 1915).
 *
 * `race_phases.test.ts` and `fixtures/race_phase_vectors.json` pin the grading.
 * What this spec pins is the rendered behaviour: the section appears only for
 * a run that carries a `metadata.pacing_strategy` this build can read, it
 * names the preset, the goal and every phase, it shows the verdict pill, a
 * trackless run keeps its targets and says why nothing is graded, and the
 * pace cells follow the miles preference.
 */

const M_PER_DEG_LAT = 111_320;
const TEN_MILE_FRACTION = 16_093.44 / 42_195;

/// A meridian-aligned track of `legs` (metres at a pace in s/km), 50 m steps.
function track(startedAt: string, legs: { m: number; pace: number }[]) {
	let cumM = 0;
	let tMs = Date.parse(startedAt);
	const at = () => ({ lat: 40 + cumM / M_PER_DEG_LAT, lng: -105, ts: new Date(tMs).toISOString() });
	const out = [at()];
	for (const leg of legs) {
		const n = Math.max(1, Math.round(leg.m / 50));
		for (let i = 0; i < n; i++) {
			cumM += leg.m / n;
			tMs += Math.round((leg.m / n) * leg.pace);
			out.push(at());
		}
	}
	return out;
}

/// A 5K run under the 10-10-10 preset with a 25:00 goal: targets 5:06, 5:00
/// and 4:49 /km. The first phase runs at 4:50 and the last at 5:15 — the
/// went-out-too-fast shape.
async function seedTooFastFiveK(startedAt: string, metadata?: Record<string, unknown>) {
	const f = 5_000 * TEN_MILE_FRACTION;
	return insertRun({
		user_id: USER_A.id,
		started_at: startedAt,
		distance_m: 5_000,
		duration_s: 1_510,
		is_public: false,
		metadata: metadata ?? {
			activity_type: 'run',
			pacing_strategy: { preset: 'ten_ten_ten', distance_m: 5_000, goal_time_s: 1_500 },
		},
		track: track(startedAt, [
			{ m: f, pace: 290 },
			{ m: f, pace: 300 },
			{ m: 5_000 - 2 * f, pace: 315 },
		]),
	});
}

/// Answer both reads the app resolves the unit from — the profile column and
/// the settings bag, which wins over it — with miles, so the page renders in
/// miles without writing a preference other lanes share.
async function inMiles(page: Page, mockRoute: MockRoute) {
	const rewrite = (pathSuffix: string, patch: (row: Record<string, unknown>) => Record<string, unknown>) =>
		mockRoute(
			page,
			(url) => url.pathname.endsWith(pathSuffix),
			async (route, request) => {
				if (request.method() !== 'GET') return route.continue();
				const response = await route.fetch();
				const body = await response.json();
				await route.fulfill({
					response,
					json: Array.isArray(body) ? body.map(patch) : body == null ? body : patch(body),
				});
			}
		);
	await rewrite('/rest/v1/rpc/get_my_profile', (p) => ({ ...p, preferred_unit: 'mi' }));
	await rewrite('/rest/v1/user_settings', (row) => ({
		...row,
		prefs: { ...((row.prefs as Record<string, unknown> | null) ?? {}), preferred_unit: 'mi' },
	}));
}

test.describe('/runs/[id] — pacing strategy review', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a run under 10-10-10 that went out too fast grades every phase and says so', async ({
		page,
	}) => {
		const runId = await seedTooFastFiveK(browserDayAt(-3, 7));
		try {
			await page.goto(`/runs/${runId}`);
			const review = page.getByTestId('strategy-review');
			await expect(review).toBeVisible({ timeout: 15_000 });
			await expect(review.getByRole('heading', { name: 'Pacing strategy' })).toBeVisible();
			await expect(review.locator('.strategy-verdict')).toHaveText('Went out too fast');
			await expect(review.locator('.workout-name')).toContainText('10-10-10');
			await expect(review.locator('.workout-name')).toContainText('Goal 25:00');

			const rows = review.locator('tbody tr');
			await expect(rows).toHaveCount(3);
			await expect(rows.nth(0)).toContainText('Hold back');
			await expect(rows.nth(1)).toContainText('Settle');
			await expect(rows.nth(2)).toContainText('Race');
			await expect(rows.nth(0).locator('td').nth(1)).toHaveText('5:06 /km');
			await expect(rows.nth(0).locator('.pace-delta')).toHaveText(/^−\d+s$/);
			await expect(rows.nth(0).locator('.pace-delta')).toHaveClass(/pace-delta-amber/);
			await expect(rows.nth(1).locator('.pace-delta')).toHaveClass(/pace-delta-on/);
			await expect(rows.nth(2).locator('.pace-delta')).toHaveText(/^\+\d+s$/);
			await expect(review.locator('.splits-hint')).toContainText('1.5%');
		} finally {
			await deleteRun(runId);
		}
	});

	test('the pace cells and deltas follow the miles preference', async ({ page, mockRoute }) => {
		await inMiles(page, mockRoute);
		const runId = await seedTooFastFiveK(browserDayAt(-3, 9));
		try {
			await page.goto(`/runs/${runId}`);
			const review = page.getByTestId('strategy-review');
			await expect(review).toBeVisible({ timeout: 15_000 });
			const first = review.locator('tbody tr').nth(0);
			// 306 s/km is 8:12 per mile; the 16 s/km gap is 26 s per mile.
			await expect(first.locator('td').nth(1)).toHaveText('8:12 /mi');
			await expect(first.locator('.pace-delta')).toHaveText('−26s');
			await expect(review.locator('.workout-name')).toContainText('mi');
		} finally {
			await deleteRun(runId);
		}
	});

	test('a run with a strategy but no GPS track keeps the targets and explains the missing grades', async ({
		page,
	}) => {
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: browserDayAt(-4, 7),
			distance_m: 10_000,
			duration_s: 3_000,
			is_public: false,
			metadata: {
				activity_type: 'run',
				pacing_strategy: { preset: 'negative_split', distance_m: 10_000, goal_time_s: 3_000 },
			},
		});
		try {
			await page.goto(`/runs/${runId}`);
			const review = page.getByTestId('strategy-review');
			await expect(review).toBeVisible({ timeout: 15_000 });
			await expect(review.locator('.strategy-verdict')).toHaveCount(0);
			const rows = review.locator('tbody tr');
			await expect(rows).toHaveCount(2);
			await expect(rows.nth(0).locator('td').nth(1)).toHaveText('5:06 /km');
			await expect(rows.nth(1).locator('td').nth(1)).toHaveText('4:54 /km');
			await expect(review.locator('.strategy-note')).toHaveText(
				"This run has no timed GPS track, so its phases can't be graded."
			);
		} finally {
			await deleteRun(runId);
		}
	});

	test('a strategy preset this build does not know renders no section, and neither does no strategy', async ({
		page,
	}) => {
		const unknown = await seedTooFastFiveK(browserDayAt(-5, 7), {
			activity_type: 'run',
			pacing_strategy: { preset: 'pyramid', distance_m: 5_000, goal_time_s: 1_500 },
		});
		const none = await seedTooFastFiveK(browserDayAt(-5, 9), { activity_type: 'run' });
		try {
			for (const runId of [unknown, none]) {
				await page.goto(`/runs/${runId}`);
				// The pacing summary renders off the same track, so once it is up
				// the strategy section has had every chance to render too.
				await expect(page.locator('.pacing')).toBeVisible({ timeout: 15_000 });
				await expect(page.getByTestId('strategy-review')).toHaveCount(0);
			}
		} finally {
			await deleteRun(unknown);
			await deleteRun(none);
		}
	});
});
