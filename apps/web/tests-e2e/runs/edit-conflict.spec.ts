import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { readRow } from '../fixtures/db-read';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — the edit dialog is a compare-and-swap on the row's
 * server-stamped `updated_at` (decisions § 2147). The admin client plays a
 * second device writing the row after the page loaded it, which the
 * `runs_stamp_updated_at` trigger moves the stamp for.
 *
 *   1. The other device changed the SAME field: nothing is written, the
 *      runner is told, and the other device's value survives.
 *   2. The other device changed a DIFFERENT field: the title lands on top of
 *      it and the other change survives, with nothing to tell the runner.
 */

const ORIGINAL = { activity_type: 'run', title: 'Loaded title', notes: 'Loaded notes' };

test.describe('/runs/[id] — edit conflicts', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;

	test.afterEach(async () => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
			runId = null;
		}
	});

	async function openEditor(page: Page, id: string) {
		await page.goto(`/runs/${id}`);
		await expect(page.getByRole('heading', { name: 'Loaded title', level: 1 })).toBeVisible({
			timeout: 10_000
		});
		await page.locator('button[title="Edit"]').first().click();
		await expect(page.locator('input.edit-input')).toHaveValue('Loaded title');
	}

	async function readMetadata(id: string) {
		const admin = getAdminClient();
		const row = await readRow(
			'the edited run',
			admin.from('runs').select('metadata').eq('id', id).single()
		);
		return row.metadata as Record<string, unknown>;
	}

	test('a title changed elsewhere is not overwritten, and the runner is told', async ({ page }) => {
		const id = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			metadata: ORIGINAL
		});
		runId = id;
		await openEditor(page, id);

		const { error } = await getAdminClient()
			.from('runs')
			.update({ metadata: { ...ORIGINAL, title: 'Other device title' } })
			.eq('id', id);
		expect(error).toBeNull();

		await page.locator('input.edit-input').fill('Browser title');
		await page.getByRole('button', { name: 'Save', exact: true }).click();

		await expect(page.getByTestId('toast-live-assertive')).toContainText(
			'This run was changed elsewhere after you opened it'
		);
		await expect(
			page.getByRole('heading', { name: 'Other device title', level: 1 })
		).toBeVisible();
		await expect(page.locator('input.edit-input')).toHaveValue('Browser title');
		expect((await readMetadata(id)).title).toBe('Other device title');
	});

	test('notes changed elsewhere survive a title edit', async ({ page }) => {
		const id = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			metadata: ORIGINAL
		});
		runId = id;
		await openEditor(page, id);

		const { error } = await getAdminClient()
			.from('runs')
			.update({ metadata: { ...ORIGINAL, notes: 'Other device notes' } })
			.eq('id', id);
		expect(error).toBeNull();

		await page.locator('input.edit-input').fill('Browser title');
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.locator('input.edit-input')).toHaveCount(0);

		const metadata = await readMetadata(id);
		expect(metadata.title).toBe('Browser title');
		expect(metadata.notes).toBe('Other device notes');
	});
});
