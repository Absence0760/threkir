import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, deleteRun, insertEvent, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — organiser photos and moderation (#1150).
 *
 * USER_A owns Richmond Run Club, so they are a photo steward of its events:
 * they post a photo of the occurrence with NO run, and hide any photo in the
 * gallery. A hidden photo leaves the gallery for everyone else (USER_B here)
 * while staying in the database — and on its owner's run.
 */

const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const EVENT_START = '2025-11-11T08:00:00.000Z';

const PNG_1X1 = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
	'base64'
);

let eventId: string | null = null;
let attendeeRunId: string | null = null;

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
	if (attendeeRunId) {
		try {
			await deleteRun(attendeeRunId);
		} catch (_) {
			/* best-effort */
		}
		attendeeRunId = null;
	}
});

test.describe('organiser', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('posts an occurrence photo without picking a run', async ({ page }) => {
		const title = `e2e organiser photo ${Date.now()}`;
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: EVENT_START
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		const chooser = page.waitForEvent('filechooser');
		await page.getByTestId('event-photo-add-host').click();
		await (await chooser).setFiles({ name: 'start-line.png', mimeType: 'image/png', buffer: PNG_1X1 });

		await expect
			.poll(
				async () => {
					const { data } = await getAdminClient()
						.from('run_photos')
						.select('run_id, owner_id, event_instance_start')
						.eq('event_id', eventId);
					return (data ?? []).map((r) => [r.run_id, r.owner_id]);
				},
				{ timeout: 15_000 }
			)
			.toEqual([[null, USER_A.id]]);

		await expect(page.getByTestId('event-photo-tile')).toHaveCount(1, { timeout: 10_000 });
		await expect(page.getByText('Photos (1)')).toBeVisible();
	});

	test('hides an attendee photo; it stays listed for the organiser with Restore', async ({ page }) => {
		const title = `e2e organiser hide ${Date.now()}`;
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: EVENT_START
		});
		attendeeRunId = await insertRun({
			user_id: USER_B.id,
			started_at: '2025-11-11T08:02:00.000Z',
			duration_s: 1800,
			distance_m: 5000
		});
		const { data: photo, error } = await getAdminClient()
			.from('run_photos')
			.insert({
				run_id: attendeeRunId,
				owner_id: USER_B.id,
				storage_path: `${USER_B.id}/e2e-hide-${Date.now()}.png`,
				event_id: eventId,
				event_instance_start: EVENT_START
			})
			.select('id')
			.single();
		expect(error).toBeNull();

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		const tile = page.getByTestId('event-photo-tile');
		await expect(tile).toHaveCount(1, { timeout: 10_000 });
		await tile.getByRole('button', { name: /^Hide photo by/ }).click();

		// Reversible, so it takes the undo bar rather than a confirm, and the
		// steward keeps the tile badged so it can be restored.
		await expect(tile.getByText('Hidden')).toBeVisible();
		await expect(tile.getByRole('button', { name: 'Restore' })).toBeVisible();
		await expect(page.getByText('Photos (0)')).toBeVisible();

		await expect
			.poll(
				async () => {
					const { data } = await getAdminClient()
						.from('run_photos')
						.select('hidden_by')
						.eq('id', photo!.id)
						.single();
					return data?.hidden_by ?? null;
				},
				{ timeout: 20_000 }
			)
			.toBe(USER_A.id);

		// Not an organiser delete: the attendee's row survives.
		const { count } = await getAdminClient()
			.from('run_photos')
			.select('id', { count: 'exact', head: true })
			.eq('id', photo!.id);
		expect(count).toBe(1);
	});

	test('restores a hidden photo; it is back in the gallery for a non-organiser', async ({
		page,
		browser
	}) => {
		const title = `e2e organiser restore ${Date.now()}`;
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: EVENT_START
		});
		attendeeRunId = await insertRun({
			user_id: USER_B.id,
			started_at: '2025-11-11T08:02:00.000Z',
			duration_s: 1800,
			distance_m: 5000
		});
		const admin = getAdminClient();
		const { data: photo, error } = await admin
			.from('run_photos')
			.insert({
				run_id: attendeeRunId,
				owner_id: USER_B.id,
				storage_path: `${USER_B.id}/e2e-restore-${Date.now()}.png`,
				event_id: eventId,
				event_instance_start: EVENT_START
			})
			.select('id')
			.single();
		expect(error).toBeNull();
		const moderation = async () => {
			const { data } = await admin
				.from('run_photos')
				.select('hidden_at, hidden_by')
				.eq('id', photo!.id)
				.single();
			return data;
		};

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		const tile = page.getByTestId('event-photo-tile');
		await expect(tile).toHaveCount(1, { timeout: 10_000 });
		await tile.getByRole('button', { name: /^Hide photo by/ }).click();
		await expect
			.poll(async () => (await moderation())?.hidden_by ?? null, { timeout: 20_000 })
			.toBe(USER_A.id);

		// From the committed state, not the optimistic one: the hidden photo the
		// page reloads is the one the server answers.
		await page.reload();
		await expect(tile.getByText('Hidden')).toBeVisible({ timeout: 10_000 });
		await tile.getByRole('button', { name: 'Restore' }).click();

		await expect(tile.getByText('Hidden')).toHaveCount(0);
		await expect(tile.getByRole('button', { name: /^Hide photo by/ })).toBeVisible();
		await expect(page.getByText('Photos (1)')).toBeVisible();
		await expect
			.poll(moderation, { timeout: 15_000 })
			.toEqual({ hidden_at: null, hidden_by: null });

		// USER_C_PRO neither owns the photo nor stewards the event, so the RLS
		// hidden filter is what decides whether they see it.
		const viewerContext = await browser.newContext({ storageState: USER_C_PRO.storageStatePath });
		try {
			const viewer = await viewerContext.newPage();
			await viewer.goto(`/clubs/richmond-run-club/events/${eventId}`);
			await expect(viewer.getByRole('heading', { name: title })).toBeVisible({
				timeout: 10_000
			});
			const section = viewer.getByTestId('event-photos');
			await expect(section.getByText('Photos (1)')).toBeVisible({ timeout: 10_000 });
			await expect(viewer.getByTestId('event-photo-tile')).toHaveCount(1);
			await expect(section.getByRole('button', { name: /^Hide photo by/ })).toHaveCount(0);
		} finally {
			await viewerContext.close();
		}
	});
});

test.describe('attendee after moderation', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('Restore inside the undo window cancels the hide instead of racing it', async ({ page }) => {
		const title = `e2e organiser restore race ${Date.now()}`;
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: EVENT_START
		});
		attendeeRunId = await insertRun({
			user_id: USER_B.id,
			started_at: '2025-11-11T08:02:00.000Z',
			duration_s: 1800,
			distance_m: 5000
		});
		const admin = getAdminClient();
		const { data: photo, error } = await admin
			.from('run_photos')
			.insert({
				run_id: attendeeRunId,
				owner_id: USER_B.id,
				storage_path: `${USER_B.id}/e2e-restore-race-${Date.now()}.png`,
				event_id: eventId,
				event_instance_start: EVENT_START
			})
			.select('id')
			.single();
		expect(error).toBeNull();

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		const tile = page.getByTestId('event-photo-tile');
		await expect(tile).toHaveCount(1, { timeout: 10_000 });

		await tile.getByRole('button', { name: /^Hide photo by/ }).click();
		await expect(page.getByTestId('undo-bar')).toBeVisible();
		await tile.getByRole('button', { name: 'Restore' }).click();

		// The pending hide is cancelled, so the undo bar goes at once. Had
		// Restore saved alongside it, the bar would stay for the whole window
		// and the hide would then land over the restore.
		await expect(page.getByTestId('undo-bar')).toBeHidden({ timeout: 2_000 });
		await expect(tile.getByText('Hidden')).toHaveCount(0);

		await page.reload();
		await expect(tile).toHaveCount(1, { timeout: 10_000 });
		await expect(tile.getByText('Hidden')).toHaveCount(0);
		const { data } = await admin
			.from('run_photos')
			.select('hidden_at, hidden_by')
			.eq('id', photo!.id)
			.single();
		expect(data).toEqual({ hidden_at: null, hidden_by: null });
	});

	test('a hidden photo is gone from the gallery, and no moderation controls show', async ({ page }) => {
		const title = `e2e hidden for others ${Date.now()}`;
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: EVENT_START
		});
		const admin = getAdminClient();
		const { data: hostPhoto } = await admin
			.from('run_photos')
			.insert({
				owner_id: USER_A.id,
				storage_path: `${USER_A.id}/e2e-host-${Date.now()}.png`,
				event_id: eventId,
				event_instance_start: EVENT_START
			})
			.select('id')
			.single();
		await admin
			.from('run_photos')
			.update({ hidden_at: new Date().toISOString(), hidden_by: USER_A.id })
			.eq('id', hostPhoto!.id);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		const section = page.getByTestId('event-photos');
		await expect(section.getByText('Photos (0)')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('event-photo-tile')).toHaveCount(0);
		await expect(section.getByRole('button', { name: /^Hide photo by/ })).toHaveCount(0);
		await expect(page.getByTestId('event-photo-add-host')).toHaveCount(0);
	});
});
