import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { switchRunsToAllTime } from '../fixtures/helpers';
import { USER_A } from '../fixtures/users';
import { readCount, readRows } from '../fixtures/db-read';

/**
 * Third-party-import journey — the full life of a single imported
 * activity, walked through every run surface the import threads into and
 * the de-dupe backstop on a second import. Heavier than the per-surface
 * specs it complements (settings/integrations-connected.spec.ts's
 * planted-row connected-state UI, cross-cutting/strava-import-guards's
 * EF gates, cross-cutting/runs-external-id-dedupe's raw-INSERT 23505
 * backstop) because it threads ONE import — driven through the real
 * in-app Strava bulk-zip uploader — across the import → /runs list →
 * /runs/[id] detail → re-import-dedupe seams rather than asserting any
 * single screen or guard. Connect / disconnect live in
 * integrations-connected.spec.ts: no provider is left on a non-OAuth
 * connect path a journey could walk.
 *
 * Why the STRAVA ZIP path (not live OAuth / a sync): Strava + Garmin
 * live OAuth can't run locally (no sandbox; integrations.md — Garmin
 * OAuth is deferred entirely), so the only import that exercises the
 * real client pipeline end-to-end without a network round-trip is the
 * `importStravaZip` file uploader on /settings/integrations. We build a
 * one-activity Strava export ZIP in memory and feed it through the
 * hidden file input (same buffer-upload pattern as
 * settings/restore-backup.spec.ts), trackless (empty Filename cell) so
 * no Storage object is involved — the journey is about the scalar row +
 * its dedupe key, not the GPS trace.
 *
 *   1. IMPORT an activity via the Strava bulk-zip uploader. The ZIP has
 *      one run-type row with a unique `Activity ID`. importStravaZip
 *      writes it through saveRun with `external_id = strava:<id>` AND
 *      `metadata.strava_id = <id>` (strava-zip.ts:importOne). The in-page
 *      progress reads "1 / 1 · 1 imported · 0 skipped" and a success toast.
 *   2. THREADS the run surfaces: it appears on /runs (All-time) and its
 *      /runs/[id] detail page renders (title from the CSV Activity Name).
 *      Backend cross-check: exactly one source='strava' row carries this
 *      external_id, with the matching metadata.strava_id.
 *   3. RE-IMPORT the SAME ZIP → DE-DUPED. importStravaZip pre-fetches the
 *      user's existing strava ids (buildStravaDedupeSet pulls from BOTH
 *      metadata.strava_id and the external_id `strava:` prefix), so the
 *      row is SKIPPED, not re-inserted. The progress reads "1 / 1 ·
 *      0 imported · 1 skipped"; the backend row count for this
 *      external_id stays exactly 1 (the dedupe contract threaded, not
 *      asserted as a raw 23505 like runs-external-id-dedupe does).
 *
 * No rate-limit reset needed: the zip importer has no per-user bucket
 * (only create_club / create_route are throttled, migration 20260907_001).
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

/**
 * Render a Date as Strava's documented "Activity Date" cell shape — the
 * no-zone, UTC-wall-clock "Mon D, YYYY, h:mm:ss AM" string that
 * parseStravaCsvDateToIso reads back as a UTC instant (strava-zip-date.ts).
 * Built from UTC getters so the round-trip lands on the exact instant we
 * passed in, independent of the test machine's local zone.
 */
function stravaActivityDate(d: Date): string {
	const months = [
		'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
		'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
	];
	let hour = d.getUTCHours();
	const ampm = hour >= 12 ? 'PM' : 'AM';
	hour = hour % 12;
	if (hour === 0) hour = 12;
	const mm = String(d.getUTCMinutes()).padStart(2, '0');
	const ss = String(d.getUTCSeconds()).padStart(2, '0');
	return `${months[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}, ${hour}:${mm}:${ss} ${ampm}`;
}

/**
 * Build a one-activity Strava bulk-export ZIP in memory. The export's
 * root `activities.csv` is the only thing the importer requires; an
 * empty Filename cell imports the row trackless (no Storage object), so
 * the fixture stays a few bytes. `Activity ID` is the dedupe key; the
 * Distance column is km, Moving Time is seconds (strava-zip.ts).
 *
 * The `Activity Date` cell becomes the run's `started_at` (via
 * importOne → parseStravaCsvDateToIso). It is dated at `opts.startedAt`
 * — passed as NOW by the caller so the imported run sorts to the TOP of
 * the desc-sorted /runs All-time list (which paginates newest-first in
 * 50-row pages); a far-past date would bury it below page 1 on USER_A's
 * ~225-run account and the `.run-card` assertion would never see it.
 * The date is independent of the dedupe key (`Activity ID`), so the
 * re-import still de-dupes regardless of the timestamp.
 */
async function buildStravaZip(opts: {
	stravaId: string;
	name: string;
	startedAt: Date;
}): Promise<Buffer> {
	const JSZip = (await import('jszip')).default;
	const zip = new JSZip();
	// One header row + one run-type data row, no Filename → trackless.
	// Column names match the case-insensitive lookups in
	// strava-zip-header.ts (Activity ID / Activity Name / Activity Type /
	// Activity Date / Filename / Distance / Moving Time).
	const csv = [
		'Activity ID,Activity Date,Activity Name,Activity Type,Filename,Distance,Moving Time,Elevation Gain',
		`${opts.stravaId},"${stravaActivityDate(opts.startedAt)}","${opts.name}",Run,,5.00,1500,42`,
		''
	].join('\n');
	zip.file('activities.csv', csv);
	const arr = await zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE' });
	return Buffer.from(arr);
}

test.describe('third-party import journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('import a Strava activity → threads /runs + detail → re-import de-duped', async ({
		page
	}) => {
		const admin = getAdminClient();
		// Unique strava id so reruns never collide with a leftover row, and
		// so the dedupe assertion is about THIS import, not seed data.
		const stravaId = `${Date.now()}${Math.floor(Math.random() * 1000)}`;
		const externalId = `strava:${stravaId}`;
		const activityName = uniqueText('e2e-import-journey-run');
		// Date the imported activity at NOW so it sorts to the top of the
		// desc-by-started_at /runs All-time list (paginated 50/page) on
		// USER_A's ~225-run account — otherwise the .run-card lands below
		// page 1 and the visibility assertion never resolves. Shared by
		// both the import and the re-import build so the dedupe step sees
		// the identical row (the Activity ID, not the date, is the key).
		const startedAt = new Date();

		// Captured so every surface addresses the SAME run and teardown
		// sweeps exactly what this test planted.
		let runId = '';

		try {
			// ── 1. Import an activity via the Strava bulk-zip uploader ───
			await test.step('USER_A imports a one-activity Strava export ZIP', async () => {
				await page.goto('/settings/integrations');
				const zip = await buildStravaZip({ stravaId, name: activityName, startedAt });

				// The bulk-import section's hidden <input type="file"> is the
				// real import trigger (the visible "Choose Strava export zip"
				// label proxies to it). Scope to the Strava bulk-import card
				// so we don't grab the Garmin uploader's input.
				const stravaBulkCard = page
					.locator('section.bulk-import')
					.filter({ hasText: 'Bulk import from a Strava export' });
				await expect(stravaBulkCard).toBeVisible({ timeout: 10_000 });

				await stravaBulkCard.locator('input[type="file"]').setInputFiles({
					name: 'strava_export.zip',
					mimeType: 'application/zip',
					buffer: zip
				});

				// importStravaZip drives the .zip-progress block: "1 / 1"
				// done, 1 imported, 0 skipped. Assert the import landed (the
				// success summary), then the toast as a second signal.
				const progress = stravaBulkCard.locator('.zip-status');
				await expect(progress).toContainText('1 / 1', { timeout: 15_000 });
				await expect(progress).toContainText('1 imported');
				await expect(progress).toContainText('0 skipped');
				await expect(page.locator('.toast-success')).toContainText(
					/1 new/i,
					{ timeout: 10_000 }
				);

				// Backend: exactly one strava run landed with this dedupe
				// key + the canonical metadata.strava_id (both written by
				// importOne — the two keys buildStravaDedupeSet later reads).
				const rows = await readRows(
					'runs by user_id+external_id',
					admin
						.from('runs')
						.select('id, user_id, source, external_id, metadata')
						.eq('user_id', USER_A.id)
						.eq('external_id', externalId)
				);
				expect(rows).toHaveLength(1);
				expect(rows![0].user_id).toBe(USER_A.id);
				expect(rows![0].source).toBe('strava');
				expect(
					(rows![0].metadata as Record<string, unknown>)?.strava_id
				).toBe(stravaId);
				runId = rows![0].id as string;
			});

			// ── 2. The imported run threads the run surfaces ────────────
			await test.step('the imported run appears on /runs (All-time) and its detail page', async () => {
				await page.goto('/runs');
				await switchRunsToAllTime(page);
				await expect(
					page.locator(`.run-card[href$="${runId}"]`)
				).toBeVisible({ timeout: 10_000 });

				// Detail page mounts; the <h1> derives from metadata.title
				// (the CSV Activity Name, written via saveRun's title arg).
				await page.goto(`/runs/${runId}`);
				await expect(
					page.getByRole('heading', { name: activityName, level: 1 })
				).toBeVisible({ timeout: 10_000 });
				// The detail stat grid renders (.key-stat-value is the
				// detail-page stat class) — a real run, not a husk.
				await expect(
					page.locator('.key-stat-value').first()
				).toBeVisible({ timeout: 10_000 });
			});

			// ── 3. Re-import the SAME ZIP → de-duped (no second row) ────
			await test.step('re-importing the identical ZIP is de-duped — skipped, not re-inserted', async () => {
				await page.goto('/settings/integrations');
				const stravaBulkCard = page
					.locator('section.bulk-import')
					.filter({ hasText: 'Bulk import from a Strava export' });
				await expect(stravaBulkCard).toBeVisible({ timeout: 10_000 });

				// Identical ZIP: same Activity ID → same strava_id /
				// external_id. importStravaZip's pre-fetch dedupe Set
				// (buildStravaDedupeSet over the user's existing rows) now
				// contains this id, so the row is SKIPPED.
				const zip = await buildStravaZip({ stravaId, name: activityName, startedAt });
				await stravaBulkCard.locator('input[type="file"]').setInputFiles({
					name: 'strava_export.zip',
					mimeType: 'application/zip',
					buffer: zip
				});

				// Progress: 1 / 1 done, 0 imported, 1 skipped.
				const progress = stravaBulkCard.locator('.zip-status');
				await expect(progress).toContainText('1 / 1', { timeout: 15_000 });
				await expect(progress).toContainText('0 imported');
				await expect(progress).toContainText('1 skipped');
				await expect(page.locator('.toast-success')).toContainText(
					/0 new/i,
					{ timeout: 10_000 }
				);

				// UI: still exactly one matching row in the list.
				await page.goto('/runs');
				await switchRunsToAllTime(page);
				await expect(
					page.locator(`.run-card[href$="${runId}"]`)
				).toHaveCount(1);

				// Backend: the dedupe held — exactly one row for the key,
				// not two. This is THE contract this journey exists to thread.
				const count = await readCount(
					'runs by user_id+external_id',
					admin
						.from('runs')
						.select('*', { count: 'exact', head: true })
						.eq('user_id', USER_A.id)
						.eq('external_id', externalId)
				);
				expect(count).toBe(1);
			});
		} finally {
			if (runId) await admin.from('runs').delete().eq('id', runId);
		}
	});
});
