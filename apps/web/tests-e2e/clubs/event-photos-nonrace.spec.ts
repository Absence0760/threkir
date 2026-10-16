import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, deleteRun, insertEvent, insertRun } from '../fixtures/simulate';
import { USER_B } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — event photo gallery on a NON-race event, as an
 * attendee (a plain member, not a steward).
 *
 * Regression for persona round-5 runner-social-group: the "Add photo"
 * affordance used to be gated behind having a finisher result row at the
 * event (the race-only path), so a weekly social group run — where nobody
 * submits results — never showed it. Any signed-in user can add a photo by
 * picking which of their own runs it belongs to.
 *
 * Since #1150 the picker offers only runs that STARTED inside the
 * occurrence's photo window ([start − 2 h, start + 24 h)), because the
 * database refuses any other. The event sits at a fixed past instant no
 * seeded run is near, so the two runs inserted here are the whole picture.
 */

const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const EVENT_START = '2025-11-04T08:00:00.000Z';
const IN_WINDOW_RUN = '2025-11-04T08:05:00.000Z';
const OUT_OF_WINDOW_RUN = '2025-10-28T08:05:00.000Z';

// 1x1 transparent PNG.
const PNG_1X1 = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
	'base64'
);

test.describe('/clubs/[slug]/events/[id] — non-race photo gallery', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let eventId: string | null = null;
	const runIds: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (eventId) {
			await admin.from('run_photos').delete().eq('event_id', eventId);
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* best-effort */
			}
			eventId = null;
		}
		for (const id of runIds.splice(0)) {
			try {
				await deleteRun(id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	async function seed(title: string) {
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
			title,
			starts_at: EVENT_START
		});
		runIds.push(
			await insertRun({ user_id: USER_B.id, started_at: IN_WINDOW_RUN, duration_s: 1800, distance_m: 5000 }),
			await insertRun({ user_id: USER_B.id, started_at: OUT_OF_WINDOW_RUN, duration_s: 1800, distance_m: 7000 })
		);
	}

	test('the run picker offers only the run that started during the occurrence', async ({ page }) => {
		const title = `e2e group-run photo ${Date.now()}`;
		await seed(title);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		// A plain member is not a steward: no run-less upload.
		await expect(page.getByTestId('event-photo-add-host')).toHaveCount(0);

		const addPhoto = page.getByRole('button', { name: 'Add photo' });
		await expect(addPhoto).toBeVisible({ timeout: 10_000 });
		await addPhoto.click();

		const picker = page.locator('.picker', { hasText: 'Which run is this photo from?' });
		await expect(picker).toBeVisible({ timeout: 10_000 });
		await expect(picker.locator('button.run-option')).toHaveCount(1, { timeout: 10_000 });
	});

	test('picking the run and a file lands a run_photos row tagged to the event', async ({ page }) => {
		const title = `e2e group-run upload ${Date.now()}`;
		await seed(title);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Add photo' }).click();

		const picker = page.locator('.picker', { hasText: 'Which run is this photo from?' });
		await expect(picker.locator('button.run-option')).toHaveCount(1, { timeout: 10_000 });

		// Picking a run fires the hidden file input's .click() in JS, which
		// opens a native chooser — catch it via the filechooser event.
		const chooser = page.waitForEvent('filechooser');
		await picker.locator('button.run-option').first().click();
		await (await chooser).setFiles({ name: 'group-run.png', mimeType: 'image/png', buffer: PNG_1X1 });

		await expect
			.poll(
				async () => {
					const { data } = await getAdminClient()
						.from('run_photos')
						.select('id, run_id')
						.eq('event_id', eventId)
						.eq('owner_id', USER_B.id);
					return data?.map((r) => r.run_id) ?? [];
				},
				{ timeout: 15_000 }
			)
			.toEqual([runIds[0]]);
	});
});
