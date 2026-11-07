import { expect, test } from '../fixtures/test';

import { deleteRun, insertLivePings, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /live/[id] ping ordering and weak-GPS fixes (issue #1300 BUG-003 / BUG-007).
 *
 * The page used to append every ping in arrival order, so a ping that
 * arrived after a newer one rewound the stat strip and drew a spike back to
 * an old position. Every ping now lands in time order, and only the newest
 * drives the readout. A weak-GPS ping (the recorder's estimator fix while
 * no fix clears its 20 m gate) renders as an approximate position.
 */

const OUT_OF_ZONE: Array<{ lat: number; lng: number }> = [
	{ lat: -37.816, lng: 144.97 },
	{ lat: -37.8175, lng: 144.972 },
	{ lat: -37.82, lng: 144.975 },
	{ lat: -37.823, lng: 144.978 }
];

test.describe('/live/[id] — ping order and weak GPS (anon)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('a ping that arrives after a newer one does not rewind the readout', async ({ page }) => {
		const now = Date.now();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(now - 10 * 60 * 1000).toISOString(),
			distance_m: 0,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ ...OUT_OF_ZONE[0], distance_m: 1_000, elapsed_s: 300, at: new Date(now - 30_000).toISOString() },
					{ ...OUT_OF_ZONE[2], distance_m: 3_000, elapsed_s: 900, at: new Date(now - 10_000).toISOString() }
				]
			});

			await page.goto(`/live/${runId}`);
			const distance = page.getByTestId('live-distance');
			await expect(page.locator('.live-badge')).toHaveClass(/active/, { timeout: 10_000 });
			await expect(distance).toContainText('3.0');

			// Late: stamped between the two already shown.
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ ...OUT_OF_ZONE[1], distance_m: 2_000, elapsed_s: 600, at: new Date(now - 20_000).toISOString() }
				]
			});
			// Then a genuinely newer one. The feed delivers in insert order, so
			// once this one shows, the late one has already been handled.
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ ...OUT_OF_ZONE[3], distance_m: 4_500, elapsed_s: 1_350, at: new Date().toISOString() }
				]
			});
			await expect(distance).toContainText('4.5', { timeout: 20_000 });
		} finally {
			await deleteRun(runId);
		}
	});

	test('a late ping alone leaves the newest readout in place', async ({ page }) => {
		const now = Date.now();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(now - 10 * 60 * 1000).toISOString(),
			distance_m: 0,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ ...OUT_OF_ZONE[2], distance_m: 3_000, elapsed_s: 900, at: new Date(now - 5_000).toISOString() }
				]
			});
			await page.goto(`/live/${runId}`);
			const distance = page.getByTestId('live-distance');
			await expect(distance).toContainText('3.0', { timeout: 10_000 });

			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ ...OUT_OF_ZONE[0], distance_m: 1_000, elapsed_s: 300, at: new Date(now - 60_000).toISOString() }
				]
			});
			// Outlast realtime delivery and one poll-fallback cycle.
			await page.waitForTimeout(12_000);
			await expect(distance).toContainText('3.0');
			await expect(page.getByTestId('runner-timer')).toContainText('15:00');
		} finally {
			await deleteRun(runId);
		}
	});

	test('a weak-GPS ping goes live and says the position is approximate', async ({ page }) => {
		const now = Date.now();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(now - 5 * 60 * 1000).toISOString(),
			distance_m: 0,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{
						...OUT_OF_ZONE[0],
						distance_m: 400,
						elapsed_s: 240,
						at: new Date(now - 2_000).toISOString(),
						weak_gps: true
					}
				]
			});
			await page.goto(`/live/${runId}`);
			await expect(page.locator('.live-badge')).toHaveClass(/active/, { timeout: 10_000 });
			await expect(page.getByTestId('weak-gps')).toContainText(/weak GPS/i);
			await expect(page.getByTestId('live-distance')).toContainText('400 m');
		} finally {
			await deleteRun(runId);
		}
	});
});
