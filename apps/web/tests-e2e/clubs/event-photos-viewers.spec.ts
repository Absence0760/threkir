import { expect, test } from '../fixtures/test';
import { createClient } from '@supabase/supabase-js';

import { readRows } from '../fixtures/db-read';
import { getAdminClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { deleteEvent, deleteRun, insertEvent, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — the event gallery as seen by the viewers the
 * organiser and attendee specs do not cover: a signed-out visitor, a photo
 * owner whose photo a steward hid, and a plain club member looking at other
 * people's photos.
 *
 * The gallery reads through `event_gallery_photos` (decisions § 1906), which
 * is granted to `anon`, so the signed-out case drives that grant end to end.
 * USER_A owns Richmond Run Club (a steward); USER_B is an active `member` of
 * it (not a steward); USER_C_PRO is not a member.
 */

const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const EVENT_START = '2025-11-18T08:00:00.000Z';
const IN_WINDOW_RUN = '2025-11-18T08:04:00.000Z';

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

async function seedEvent(title: string, opts: { membersOnly?: boolean } = {}) {
	eventId = await insertEvent({
		club_id: RICHMOND_RUN_CLUB_ID,
		author_id: USER_A.id,
		title,
		starts_at: EVENT_START
	});
	if (opts.membersOnly) {
		const { error } = await getAdminClient().from('events').update({ is_public: false }).eq('id', eventId);
		expect(error).toBeNull();
	}
	return eventId;
}

async function seedPhoto(opts: {
	owner: string;
	runPublic?: boolean;
	withRun?: boolean;
	hiddenBy?: string;
	tag: string;
}) {
	let runId: string | null = null;
	if (opts.withRun !== false) {
		runId = await insertRun({
			user_id: opts.owner,
			started_at: IN_WINDOW_RUN,
			duration_s: 1500,
			distance_m: 5000,
			is_public: opts.runPublic ?? false
		});
		runIds.push(runId);
	}
	const admin = getAdminClient();
	const { data, error } = await admin
		.from('run_photos')
		.insert({
			run_id: runId,
			owner_id: opts.owner,
			storage_path: `${opts.owner}/e2e-${opts.tag}-${Date.now()}.png`,
			event_id: eventId,
			event_instance_start: EVENT_START
		})
		.select('id')
		.single();
	expect(error).toBeNull();
	if (opts.hiddenBy) {
		const { error: hideError } = await admin
			.from('run_photos')
			.update({ hidden_at: new Date().toISOString(), hidden_by: opts.hiddenBy })
			.eq('id', data!.id);
		expect(hideError).toBeNull();
	}
	return data!.id as string;
}

test.describe('signed out', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	// The consent banner would sit over the gallery; its own specs cover it.
	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem('cookie_consent', JSON.stringify({ choice: 'accepted', timestamp: Date.now() }));
		});
	});

	test('a public event shows the unhidden photos and no moderation or upload controls', async ({ page }) => {
		const title = `e2e anon gallery ${Date.now()}`;
		await seedEvent(title);
		await seedPhoto({ owner: USER_A.id, withRun: false, tag: 'anon-host' });
		await seedPhoto({
			owner: USER_C_PRO.id,
			runPublic: true,
			tag: 'anon-attendee'
		});
		// Hidden, and on a PUBLIC run, so the run-path policy alone would hand it
		// to an anonymous reader; only the gallery read keeps it out.
		await seedPhoto({
			owner: USER_B.id,
			runPublic: true,
			hiddenBy: USER_A.id,
			tag: 'anon-hidden'
		});

		const galleryStatuses: number[] = [];
		page.on('response', (r) => {
			if (r.url().includes('/rest/v1/rpc/event_gallery_photos')) galleryStatuses.push(r.status());
		});
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		const section = page.getByTestId('event-photos');
		await expect(section.getByText('Photos (2)')).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByTestId('event-photo-tile')).toHaveCount(2);
		await expect(page.getByTestId('event-photos-error')).toHaveCount(0);
		await expect(section.getByText('Hidden', { exact: true })).toHaveCount(0);
		await expect(section.getByRole('button', { name: /^Hide photo by/ })).toHaveCount(0);
		await expect(section.getByRole('button', { name: 'Restore' })).toHaveCount(0);
		await expect(section.getByRole('button', { name: 'Delete' })).toHaveCount(0);
		await expect(page.getByTestId('event-photo-add-host')).toHaveCount(0);
		await expect(page.getByTestId('event-photo-add-run')).toHaveCount(0);
		// Anonymous, so the anon grant on the gallery read is what all of the
		// above stood on: the page asked it, and it answered.
		expect(galleryStatuses.length).toBeGreaterThan(0);
		expect(new Set(galleryStatuses)).toEqual(new Set([200]));
	});

	test('a members-only event shows no event and no photos', async ({ page }) => {
		const title = `e2e anon members-only gallery ${Date.now()}`;
		await seedEvent(title, { membersOnly: true });
		await seedPhoto({ owner: USER_A.id, withRun: false, tag: 'private-host' });
		await seedPhoto({
			owner: USER_B.id,
			runPublic: false,
			tag: 'private-attendee'
		});
		// On a PUBLIC run: readable through the run path, so only the gallery
		// read's own event-visibility check keeps a members-only event's
		// photo list from an outsider (20270807000004).
		await seedPhoto({
			owner: USER_C_PRO.id,
			runPublic: true,
			tag: 'private-public-run'
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: 'Event not found' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByRole('heading', { name: title })).toHaveCount(0);
		await expect(page.getByTestId('event-photos')).toHaveCount(0);
		await expect(page.getByTestId('event-photo-tile')).toHaveCount(0);

		// The page not asking is not the database refusing: an anonymous caller
		// that skips the page and asks the gallery read directly gets nothing.
		const { url, anonKey } = loadSupabaseEnv();
		const anon = createClient(url, anonKey, {
			auth: { persistSession: false, autoRefreshToken: false }
		});
		const rows = await readRows(
			'event_gallery_photos as anon',
			anon.rpc('event_gallery_photos', {
				p_event_id: eventId!,
				p_instance: EVENT_START
			})
		);
		expect(rows).toEqual([]);
	});
});

test.describe('club member who is not a steward', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('sees their own hidden photo badged Hidden, with no Restore', async ({ page }) => {
		const title = `e2e owner hidden ${Date.now()}`;
		await seedEvent(title);
		await seedPhoto({
			owner: USER_B.id,
			hiddenBy: USER_A.id,
			tag: 'owner-hidden'
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({
			timeout: 10_000
		});

		const section = page.getByTestId('event-photos');
		const tile = page.getByTestId('event-photo-tile');
		await expect(tile).toHaveCount(1, { timeout: 10_000 });
		// The count is what everyone else sees, so the owner's hidden photo is not in it.
		await expect(section.getByText('Photos (0)')).toBeVisible();
		await expect(tile.getByText('Hidden', { exact: true })).toBeVisible();
		// Restoring is the steward's call, not the owner's; the owner can still delete.
		await expect(tile.getByRole('button', { name: 'Restore' })).toHaveCount(0);
		await expect(tile.getByRole('button', { name: /^Hide photo by/ })).toHaveCount(0);
		await expect(tile.getByRole('button', { name: 'Delete' })).toBeVisible();
	});

	test('sees no Hide control on anyone’s photo, and Delete only on their own', async ({ page }) => {
		const title = `e2e member no hide ${Date.now()}`;
		await seedEvent(title);
		await seedPhoto({ owner: USER_A.id, withRun: false, tag: 'member-host' });
		await seedPhoto({
			owner: USER_C_PRO.id,
			runPublic: true,
			tag: 'member-other'
		});
		await seedPhoto({ owner: USER_B.id, tag: 'member-own' });

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({
			timeout: 10_000
		});

		const section = page.getByTestId('event-photos');
		await expect(page.getByTestId('event-photo-tile')).toHaveCount(3, {
			timeout: 10_000
		});
		await expect(section.getByText('Photos (3)')).toBeVisible();
		// The roster has loaded by now, so a member role that leaked into the
		// steward check would already have drawn its buttons.
		await expect(section.getByRole('button', { name: /^Hide photo by/ })).toHaveCount(0);
		await expect(section.getByRole('button', { name: 'Hide', exact: true })).toHaveCount(0);
		await expect(page.getByTestId('event-photo-add-host')).toHaveCount(0);

		const deletes = section.getByRole('button', { name: 'Delete' });
		await expect(deletes).toHaveCount(1);
		await expect(
			page.getByTestId('event-photo-tile').filter({ hasText: 'Alex Chen' }).getByRole('button', { name: 'Delete' })
		).toBeVisible();
	});
});
