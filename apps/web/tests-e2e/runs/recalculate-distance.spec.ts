import { expect, test } from '../fixtures/mock-route';

import { browserDayAt } from '../fixtures/dates';
import { readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /runs/[id] — "Recalculate distance" (docs/features/gps_distance.md § Server
 * recompute).
 *
 * The owner of an app-recorded run with a stored track can ask the server to
 * re-derive its distance with the GPS distance estimator. The action goes
 * through a ConfirmDialog, calls `request_distance_recompute`, and says what
 * happened either way. It is not offered on an import, on a pedometer
 * distance, on a run already on `kalman_v3`, on a trackless run, or to anyone
 * but the owner. A recomputed run shows the recorder's original figure.
 */

const TRACK_START_MS = Date.parse(browserDayAt(-1, 7));
const TRACK = Array.from({ length: 6 }, (_, i) => ({
	lat: 51.46 + i * 0.0005,
	lng: -0.3,
	ele: 100,
	ts: new Date(TRACK_START_MS + i * 60_000).toISOString(),
}));

async function recomputeJobs(runId: string): Promise<unknown[]> {
	return readRows(
		'distance_recompute jobs for the run',
		getAdminClient()
			.from('jobs')
			.select('id, status, payload')
			.eq('kind', 'distance_recompute')
			.eq('payload->>run_id', runId),
	);
}

const runIds: string[] = [];

test.afterEach(async () => {
	const admin = getAdminClient();
	while (runIds.length) {
		const id = runIds.pop()!;
		try {
			await admin.from('jobs').delete().eq('kind', 'distance_recompute').eq('payload->>run_id', id);
			await deleteRun(id);
		} catch (_) {
			/* best-effort */
		}
	}
});

async function plant(opts: {
	title: string;
	source?: 'app' | 'strava';
	metadata?: Record<string, unknown>;
	track?: boolean;
	is_public?: boolean;
}): Promise<string> {
	const id = await insertRun({
		user_id: USER_A.id,
		started_at: browserDayAt(-1, 7),
		distance_m: 6_309,
		duration_s: 1_800,
		source: opts.source ?? 'app',
		is_public: opts.is_public ?? false,
		metadata: { activity_type: 'run', title: opts.title, ...(opts.metadata ?? {}) },
		track: opts.track === false ? undefined : TRACK,
	});
	runIds.push(id);
	return id;
}

test.describe('owner', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('confirming queues one recompute job and says to refresh', async ({ page }) => {
		const id = await plant({ title: 'Inflated 5k' });

		await page.goto(`/runs/${id}`);
		await expect(page.getByRole('heading', { name: 'Inflated 5k' })).toBeVisible({
			timeout: 10_000,
		});

		const button = page.getByTestId('recalculate-distance');
		await expect(button).toBeVisible();
		await button.click();

		const dialog = page.getByTestId('recalculate-distance-dialog');
		await expect(dialog).toBeVisible();
		await expect(dialog).toContainText('improved GPS filter');
		await expect(dialog).toContainText('originally recorded distance is kept');
		await dialog.getByRole('button', { name: 'Recalculate', exact: true }).click();

		await expect(page.locator('.toast', { hasText: /Recalculating — refresh in a minute/ })).toBeVisible({
			timeout: 10_000,
		});
		await expect(dialog).toBeHidden();
		await expect(button).toHaveCount(0);

		const jobs = await recomputeJobs(id);
		expect(jobs, 'exactly one distance_recompute job for the run').toHaveLength(1);
		expect((jobs[0] as { payload: { user_id: string } }).payload.user_id).toBe(USER_A.id);
	});

	test('cancelling the dialog leaves the action in place', async ({ page }) => {
		const id = await plant({ title: 'Cancel me' });

		await page.goto(`/runs/${id}`);
		await expect(page.getByRole('heading', { name: 'Cancel me' })).toBeVisible({ timeout: 10_000 });

		await page.getByTestId('recalculate-distance').click();
		const dialog = page.getByTestId('recalculate-distance-dialog');
		await expect(dialog).toBeVisible();
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(dialog).toBeHidden();
		await expect(page.getByTestId('recalculate-distance')).toBeVisible();
	});

	test('a failed request is surfaced and the action stays offered', async ({ page, mockRoute }) => {
		const id = await plant({ title: 'Server says no' });

		await mockRoute(page, '**/rest/v1/rpc/request_distance_recompute*', (route) =>
			route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ code: 'XX000', message: 'worker queue unavailable' }),
			}),
		);

		await page.goto(`/runs/${id}`);
		await expect(page.getByRole('heading', { name: 'Server says no' })).toBeVisible({
			timeout: 10_000,
		});
		await page.getByTestId('recalculate-distance').click();
		await page
			.getByTestId('recalculate-distance-dialog')
			.getByRole('button', { name: 'Recalculate', exact: true })
			.click();

		await expect(
			page.locator('.toast', { hasText: /Couldn't recalculate distance: worker queue unavailable/ }),
		).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('recalculate-distance')).toBeVisible();
	});

	test('a recomputed run shows the original distance and is not offered again', async ({ page }) => {
		const id = await plant({
			title: 'Already fixed',
			metadata: {
				distance_estimator: 'kalman_v3',
				distance_recorded_m: 6_308,
				distance_recomputed_at: browserDayAt(0, 6),
			},
		});

		await page.goto(`/runs/${id}`);
		await expect(page.getByRole('heading', { name: 'Already fixed' })).toBeVisible({
			timeout: 10_000,
		});
		await expect(page.getByTestId('distance-recorded-note')).toContainText('Originally recorded:');
		await expect(page.getByTestId('distance-recorded-note')).toContainText(/\d/);
		await expect(page.getByTestId('recalculate-distance')).toHaveCount(0);
	});

	test('imports, pedometer, live-stamped and trackless runs are not offered the action', async ({
		page,
	}) => {
		const cases = [
			await plant({ title: 'From Strava', source: 'strava' }),
			await plant({ title: 'Pedometer run', metadata: { distance_source: 'pedometer' } }),
			await plant({ title: 'Stamped live', metadata: { distance_estimator: 'kalman_v1' } }),
			await plant({ title: 'No track', track: false }),
		];
		const titles = ['From Strava', 'Pedometer run', 'Stamped live', 'No track'];

		for (const [i, id] of cases.entries()) {
			await page.goto(`/runs/${id}`);
			await expect(page.getByRole('heading', { name: titles[i] })).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('recalculate-distance'), titles[i]).toHaveCount(0);
		}
	});
});

test.describe('non-owner', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test("someone else's public run is not offered the action", async ({ page, mockRoute }) => {
		// The non-owner branch mounts RunShareView, whose track comes through
		// the clip-public-track Edge Function; stub it so the spec does not
		// depend on the clipping path.
		await mockRoute(page, '**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] }),
			}),
		);
		const id = await plant({ title: 'Not yours', is_public: true });

		await page.goto(`/runs/${id}`);
		await expect(page.locator('.other-run')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('recalculate-distance')).toHaveCount(0);
	});
});
