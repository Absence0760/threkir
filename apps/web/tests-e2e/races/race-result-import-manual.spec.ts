import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';
import { readMaybeRow, readRows } from '../fixtures/db-read';

/**
 * Auto-match-on-record + manual paste import (race_calendar.md). A same-day,
 * same-distance-band race listing at the run's GPS start makes the run-detail
 * page surface the inform-tier "Was this the {race}?" prompt. The run carries a
 * track because `race_match_candidates` returns nothing for a run with no start
 * point (issue #1389): a trackless run is offered no race. Confirming with a pasted chip time
 * enriches the existing run row in place (no duplicate run) and renders the
 * official result. The race metadata stays owner-only on a private run.
 */

test.describe('/runs/[id] — race result import', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const stamp = Date.now();
	const raceName = `E2E Match Marathon ${stamp}`;
	const day = '2027-04-18';
	// Hopkinton, where the run's track starts and where the listing sits.
	const start = { lat: 42.2295, lng: -71.5197 };
	let listingId: string | null = null;
	let runId: string | null = null;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data } = await admin
			.from('race_listings')
			.insert({
				provider: 'manual',
				name: raceName,
				race_date: day,
				distance_m: 42195,
				location_label: 'Boston, MA',
				location_point: `SRID=4326;POINT(${start.lng} ${start.lat})`,
				is_verified: true
			})
			.select('id')
			.single();
		listingId = (data as { id: string }).id;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
		}
		if (listingId) await admin.from('race_listings').delete().eq('id', listingId);
	});

	test('auto-match prompt → paste enriches the run + renders the official result', async ({
		page
	}) => {
		// A marathon recorded on the race's date → same day + same band match.
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: `${day}T13:00:00.000Z`,
			distance_m: 42_100,
			duration_s: 14_400,
			is_public: false,
			metadata: { activity_type: 'run', title: 'Marathon attempt' },
			track: [
				{ lat: start.lat, lng: start.lng, ts: `${day}T13:00:00.000Z` },
				{ lat: start.lat, lng: start.lng + 0.001, ts: `${day}T13:00:30.000Z` }
			]
		});

		await page.goto(`/runs/${runId}`);

		// The inform-tier prompt offers the matched race.
		const prompt = page.getByTestId('race-match-prompt');
		await expect(prompt).toBeVisible({ timeout: 10_000 });
		await expect(prompt).toContainText(raceName);

		// Confirm → a manual listing has no provider pull, so the paste form opens.
		await page.getByTestId('match-confirm').click();
		await page.getByTestId('match-chip').fill('3:21:45');
		await page.getByTestId('match-place').fill('128');
		await page.getByTestId('match-save').click();

		// The official result renders from the enriched run row.
		const result = page.getByTestId('race-result');
		await expect(result).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('race-result-chip')).toHaveText('3:21:45');

		// No duplicate run was created; the existing run carries the metadata +
		// the race_listing_id link (owner-only fields).
		const admin = getAdminClient();
		const runs = await readRows(
			'runs by id',
			admin
				.from('runs')
				.select('id, metadata, race_listing_id')
				.eq('id', runId)
		);
		expect(runs.length).toBe(1);
		const meta = (runs![0].metadata ?? {}) as Record<string, unknown>;
		expect(meta.chip_time).toBe('3:21:45');
		expect(meta.race_name).toBe(raceName);
		expect(runs![0].race_listing_id).toBe(listingId);

		// The owner-only race keys are stripped from the public projection.
		const pub = await readMaybeRow(
			'public_runs by id',
			admin
				.from('public_runs')
				.select('metadata, race_listing_id')
				.eq('id', runId)
				.maybeSingle()
		);
		// Private run → not in public_runs at all; either way no chip_time leaks.
		if (pub) {
			const pmeta = (pub.metadata ?? {}) as Record<string, unknown>;
			expect(pmeta.chip_time).toBeUndefined();
			expect(pmeta.race_name).toBeUndefined();
		}
	});
});
