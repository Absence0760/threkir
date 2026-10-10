import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { browserDatetimeLocal } from '../fixtures/dates';
import { readRows } from '../fixtures/db-read';
import { switchRunsToAllTime } from '../fixtures/helpers';
import { USER_A } from '../fixtures/users';

/**
 * Log a run, go back to the list, log the next one — walked by clicks.
 *
 * The everyday loop of a user catching up on their week: add a run,
 * glance at it, return to the list with the detail page's "All runs"
 * link, add the next. Every other create spec (runs/list.spec.ts,
 * run-lifecycle-journey.spec.ts, dashboard-journey.spec.ts) re-enters
 * /runs with page.goto after the save, which mounts a fresh list and
 * fetches. A real user never does that: "All runs" calls history.back()
 * when the detail page was reached from /runs, so /runs comes back via
 * its SvelteKit snapshot — captured BEFORE the save — rather than a
 * fetch. This spec pins that the run just added is in the list the user
 * actually returns to, and that the second add starts from a clean form
 * and lands alongside the first.
 *
 * Both rows are swept in finally; nothing else is touched.
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('runs — add two runs back to back', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('add → detail → All runs → add again → both runs are listed', async ({ page }) => {
		const admin = getAdminClient();
		const created: string[] = [];

		// Within the last two hours so both sort to the top of Newest and
		// stay inside the rendered window whatever else the seed holds.
		const firstStart = browserDatetimeLocal(Date.now() - 2 * 3600 * 1000);
		const secondStart = browserDatetimeLocal(Date.now() - 1 * 3600 * 1000);

		const addRun = async (notes: string, startedAt: string, km: string, min: string) => {
			await page.getByRole('button', { name: '+ Add run' }).click();
			const notesField = page.locator('textarea');
			await expect(notesField).toBeVisible({ timeout: 5_000 });
			// A fresh form every time — nothing carried over from the last save.
			await expect(notesField).toHaveValue('');

			await page.locator('input[type="datetime-local"]').first().fill(startedAt);
			await page.locator('input[type="number"]').first().fill(km);
			await page.locator('input[type="number"]').nth(1).fill(min);
			await notesField.fill(notes);
			await page.locator('form button[type="submit"]').click();

			await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 10_000 });
			const id = page.url().match(/\/runs\/([0-9a-f-]+)$/)![1];
			created.push(id);
			await expect(page.locator('.run-notes')).toHaveText(notes, { timeout: 10_000 });
			return id;
		};

		const backToList = async () => {
			await page.getByRole('link', { name: /All runs/ }).first().click();
			await page.waitForURL(/\/runs$/, { timeout: 10_000 });
		};

		try {
			await test.step('reach /runs from the sidebar', async () => {
				await page.goto('/dashboard');
				await page.locator('nav.sidebar').getByRole('link', { name: 'Runs', exact: true }).click();
				await page.waitForURL(/\/runs$/, { timeout: 10_000 });
				await switchRunsToAllTime(page);
				await expect(page.locator('.run-card').first()).toBeVisible({ timeout: 10_000 });
			});

			const firstNotes = uniqueText('e2e-consecutive-first');
			const secondNotes = uniqueText('e2e-consecutive-second');
			let firstId = '';
			let secondId = '';

			await test.step('add the first run', async () => {
				firstId = await addRun(firstNotes, firstStart, '5', '25');
			});

			await test.step('All runs returns to a list that holds the first run', async () => {
				await backToList();
				await expect(page.getByLabel('Date range')).toHaveValue('all');
				await expect(
					page.locator(`.run-card[href$="${firstId}"]`),
					'the run just added must be in the list "All runs" returns to'
				).toBeVisible({ timeout: 10_000 });
			});

			await test.step('add the second run from that same list', async () => {
				secondId = await addRun(secondNotes, secondStart, '8', '42');
			});

			await test.step('both runs are listed, newest first', async () => {
				await backToList();
				const second = page.locator(`.run-card[href$="${secondId}"]`);
				const first = page.locator(`.run-card[href$="${firstId}"]`);
				await expect(second).toBeVisible({ timeout: 10_000 });
				await expect(first).toBeVisible({ timeout: 10_000 });

				const hrefs = await page.locator('.run-card').evaluateAll((cards) =>
					cards.map((c) => c.getAttribute('href') ?? '')
				);
				const secondIdx = hrefs.findIndex((h) => h.endsWith(secondId));
				const firstIdx = hrefs.findIndex((h) => h.endsWith(firstId));
				expect(secondIdx).toBeLessThan(firstIdx);
			});

			await test.step('both rows exist once each in the database', async () => {
				const rows = await readRows(
					'runs by id',
					admin.from('runs').select('id, user_id, distance_m').in('id', [firstId, secondId])
				);
				expect(rows).toHaveLength(2);
				for (const row of rows) expect(row.user_id).toBe(USER_A.id);
				const byId = new Map(rows.map((r) => [r.id, r.distance_m]));
				expect(byId.get(firstId)).toBe(5000);
				expect(byId.get(secondId)).toBe(8000);
			});
		} finally {
			if (created.length > 0) {
				await admin.from('runs').delete().in('id', created);
			}
		}
	});
});
