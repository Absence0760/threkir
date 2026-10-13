import { expect, test } from '@playwright/test';

import { browserDate } from '../fixtures/dates';
import { readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRaceListing, deleteRun, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Gun and chip time from the race calendar to the run (race_calendar.md).
 *
 * A result pasted on /races carries a chip time, a gun time, or both; the
 * import lands them as separate `runs.metadata` keys and `RunRaceResult`
 * renders each under its own label. The sibling spec
 * `race-result-import-manual.spec.ts` covers the auto-match seam with a chip
 * time alone; this one walks the calendar's own paste form, both times
 * together, and a gun time with no chip, where the duration falls back to the
 * gun and the run must not invent a chip row.
 *
 * The paste leg needs no credential, so the real `race-results-import`
 * function runs.
 */

test.describe('/races paste → /runs/[id] — gun and chip time', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const listings: string[] = [];
	const runs: string[] = [];

	test.afterEach(async () => {
		for (const id of runs.splice(0)) {
			try {
				await deleteRun(id);
			} catch (_) {
				/* best-effort */
			}
		}
		for (const id of listings.splice(0)) {
			try {
				await deleteRaceListing(id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	async function pasteResult(
		page: import('@playwright/test').Page,
		times: { chip?: string; gun?: string; bib: string }
	): Promise<{ runId: string; durationS: number }> {
		const raceName = `E2E Gun Chip ${Date.now()}-${times.bib}`;
		const listingId = await insertRaceListing({
			provider: 'manual',
			name: raceName,
			race_date: browserDate(10),
			distance_m: 21_097
		});
		listings.push(listingId);

		await page.goto('/races');
		await page.getByTestId('races-search').fill(raceName);
		const card = page.getByTestId('race-card').filter({ hasText: raceName });
		await expect(card).toBeVisible({ timeout: 15_000 });
		await card.getByTestId('race-import').click();

		await page.getByTestId('paste-bib').fill(times.bib);
		if (times.chip) await page.getByTestId('paste-chip').fill(times.chip);
		if (times.gun) await page.getByTestId('paste-gun').fill(times.gun);
		await page.getByTestId('paste-save').click();
		await expect(page.getByText('Official result imported.')).toBeVisible({ timeout: 15_000 });

		const rows = await readRows(
			'imported run',
			getAdminClient()
				.from('runs')
				.select('id, duration_s, metadata')
				.eq('user_id', USER_A.id)
				.eq('race_listing_id', listingId)
		);
		expect(rows).toHaveLength(1);
		runs.push(rows[0].id as string);
		const meta = (rows[0].metadata ?? {}) as Record<string, unknown>;
		expect(meta.chip_time ?? null).toBe(times.chip ?? null);
		expect(meta.gun_time ?? null).toBe(times.gun ?? null);
		return { runId: rows[0].id as string, durationS: rows[0].duration_s as number };
	}

	test('both times land as their own keys and render under their own labels', async ({ page }) => {
		const { runId, durationS } = await pasteResult(page, {
			chip: '1:47:23',
			gun: '1:48:01',
			bib: '4411'
		});
		// The chip time is the authoritative duration when both are known.
		expect(durationS).toBe(1 * 3600 + 47 * 60 + 23);

		await page.goto(`/runs/${runId}`);
		const result = page.getByTestId('race-result');
		await expect(result).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('race-result-chip')).toHaveText('1:47:23');
		await expect(page.getByTestId('race-result-gun')).toHaveText('1:48:01');
		await expect(result).toContainText('Chip time');
		await expect(result).toContainText('Gun time');
	});

	test('a gun time with no chip times the run and draws no chip row', async ({ page }) => {
		const { runId, durationS } = await pasteResult(page, { gun: '1:52:10', bib: '4412' });
		expect(durationS).toBe(1 * 3600 + 52 * 60 + 10);

		await page.goto(`/runs/${runId}`);
		await expect(page.getByTestId('race-result')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('race-result-gun')).toHaveText('1:52:10');
		await expect(page.getByTestId('race-result-chip')).toHaveCount(0);
	});
});
