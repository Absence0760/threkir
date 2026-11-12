import { expect, test } from '../fixtures/test';

import { readMaybeRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * The universal `show_mascot` pref (default on) hides Grisnir everywhere the
 * runner would meet him: Settings → Units & display writes it, and the run
 * share card drops him even with the mark switch on (#1360).
 *
 * Runs as a throwaway user so the pref never reaches another spec's runner.
 */

let runner: SagaUser;
let runId: string;

test.beforeAll(async () => {
	[runner] = await createSagaUsers(1, { displayNames: ['Mascot Runner'] });
	runId = await insertRun({
		user_id: runner.id,
		started_at: '2026-05-10T08:00:00Z',
		distance_m: 5_000,
		duration_s: 1_500,
		metadata: { title: 'Mascot pref run' },
		track: Array.from({ length: 8 }, (_, i) => ({
			lat: -37.8 + i * 0.001,
			lng: 144.96 + (i % 2) * 0.0008,
			ts: new Date(Date.UTC(2026, 4, 10, 8, i)).toISOString(),
		})),
	});
});

test.afterAll(async () => {
	await deleteSagaUsers([runner].filter(Boolean));
});

async function storedShowMascot(): Promise<unknown> {
	const row = await readMaybeRow(
		"the runner's universal prefs",
		getAdminClient().from('user_settings').select('prefs').eq('user_id', runner.id).maybeSingle(),
	);
	return ((row?.prefs ?? {}) as Record<string, unknown>).show_mascot;
}

test('turning Grisnir off is saved and takes him off the run share card', async ({ browser }) => {
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await context.newPage();
	try {
		await page.goto(`/runs/${runId}`);
		await page.locator('button[title="Share image"]').click();
		const dialog = page.getByTestId('run-share-image-dialog');
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
		await expect(page.getByTestId('share-card-grisnir')).toBeAttached();

		await page.goto('/settings/display');
		const toggle = page.getByTestId('show-mascot');
		await expect(toggle).toBeChecked();
		await toggle.uncheck();
		await expect.poll(storedShowMascot, { timeout: 15_000 }).toBe(false);

		await page.reload();
		await expect(page.getByTestId('show-mascot')).not.toBeChecked();

		await page.goto(`/runs/${runId}`);
		await page.locator('button[title="Share image"]').click();
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
		await expect(dialog.getByTestId('share-mark')).toBeChecked();
		await expect(page.getByTestId('share-card-grisnir')).toHaveCount(0);
	} finally {
		await context.close();
	}
});
