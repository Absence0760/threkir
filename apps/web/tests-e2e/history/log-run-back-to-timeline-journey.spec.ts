import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { browserDatetimeLocal } from '../fixtures/dates';
import { readRow } from '../fixtures/db-read';
import { USER_A } from '../fixtures/users';

/**
 * Log a run from the History timeline, then return to the timeline.
 *
 * /history's Log menu hosts RunEditor; a save navigates to the new
 * /runs/[id], and that page's "All runs" link calls history.back() when
 * it was reached from /history — so the user lands on the timeline as
 * its SvelteKit snapshot captured it, before the save. The existing
 * history specs open the editor (history-cross-modal-journey.spec.ts)
 * or plant rows server-side, and none walks the save-and-return loop.
 * This one pins that the run just logged is on the timeline the user
 * comes back to, and that it opens again from there.
 *
 * The planted row is swept in finally.
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('/history — log a run, then back to the timeline', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('History → Log run → save → All runs → the run is on the timeline', async ({ page }) => {
		const admin = getAdminClient();
		const notes = uniqueText('e2e-history-log');
		let runId = '';

		try {
			await test.step('reach /history from the sidebar', async () => {
				await page.goto('/dashboard');
				await page
					.locator('nav.sidebar')
					.getByRole('link', { name: 'History', exact: true })
					.click();
				await page.waitForURL(/\/history$/, { timeout: 10_000 });
				await expect(page.locator('a.timeline-row').first()).toBeVisible({ timeout: 10_000 });
			});

			await test.step('Log → Log run → save', async () => {
				await page.getByRole('button', { name: 'Log', exact: true }).click();
				await page.getByRole('menuitem', { name: 'Log run' }).click();
				const dialog = page.getByRole('dialog', { name: 'Add a run' });
				await expect(dialog).toBeVisible({ timeout: 5_000 });

				await dialog
					.locator('input[type="datetime-local"]')
					.first()
					.fill(browserDatetimeLocal(Date.now() - 3600 * 1000));
				await dialog.locator('input[type="number"]').first().fill('6');
				await dialog.locator('input[type="number"]').nth(1).fill('33');
				await dialog.locator('textarea').fill(notes);
				await dialog.locator('form button[type="submit"]').click();

				await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 10_000 });
				runId = page.url().match(/\/runs\/([0-9a-f-]+)$/)![1];
				await expect(page.locator('.run-notes')).toHaveText(notes, { timeout: 10_000 });

				const row = await readRow(
					'runs by id',
					admin.from('runs').select('user_id, distance_m').eq('id', runId).single()
				);
				expect(row.user_id).toBe(USER_A.id);
				expect(row.distance_m).toBe(6000);
			});

			await test.step('All runs returns to a timeline that holds the new run', async () => {
				await page.getByRole('link', { name: /All runs/ }).first().click();
				await page.waitForURL(/\/history$/, { timeout: 10_000 });

				const newRow = page.locator(`a.timeline-row[href="/runs/${runId}"]`);
				await expect(
					newRow,
					'the run just logged must be on the timeline "All runs" returns to'
				).toBeVisible({ timeout: 10_000 });

				await newRow.click();
				await page.waitForURL(new RegExp(`/runs/${runId}$`), { timeout: 10_000 });
				await expect(page.locator('.run-notes')).toHaveText(notes, { timeout: 10_000 });
			});
		} finally {
			if (runId) {
				await admin.from('runs').delete().eq('id', runId);
			}
		}
	});
});
