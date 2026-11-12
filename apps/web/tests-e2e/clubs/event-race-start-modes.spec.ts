import { expect, test } from '../fixtures/test';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';
import { readRow } from '../fixtures/db-read';

/**
 * Race start modes (#1306, decisions § 2400): the event editor's mode
 * picker, a Scheduled GO counting down to live on the server clock with no
 * organiser action, and a Self-timed window offering a runner who is not
 * going "Join and attempt".
 *
 * Every session here is created by the page's own first read
 * (ensure_race_session), not by the fixture, which is the lazy path the
 * per-minute job also takes.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const ctxOpts = { locale: 'en-GB', timezoneId: 'UTC' } as const;

test.describe('/clubs/[slug]/events/[id] — race start modes', () => {
	const created: string[] = [];

	test.afterEach(async () => {
		for (const id of created.splice(0)) {
			try {
				await deleteEvent(id);
			} catch {
				/* best-effort cleanup */
			}
		}
	});

	test('the organiser picks Scheduled GO in the editor and the offset is stored', async ({ browser }) => {
		const title = `e2e start-mode picker ${Date.now()}`;
		const eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 5 * 24 * 3600 * 1000).toISOString(),
			timezone: 'UTC'
		});
		created.push(eventId);

		const ctx = await browser.newContext({ ...ctxOpts, storageState: USER_A.storageStatePath });
		try {
			const page = await ctx.newPage();
			await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
			await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({ timeout: 10_000 });

			await page.getByTestId('edit-event').click();
			const modal = page.locator('.modal', { hasText: 'Edit event' });
			await expect(modal).toBeVisible({ timeout: 5_000 });

			await modal.getByTestId('race-start-mode-scheduled').check();
			await expect(modal.getByTestId('race-go-time')).toBeVisible();
			await modal.getByRole('button', { name: 'Save changes' }).click();
			await expect(modal).toHaveCount(0, { timeout: 10_000 });

			const row = await readRow(
				'events race settings',
				getAdminClient()
					.from('events')
					.select('race_start_mode, race_scheduled_offset_s, race_window_length_s')
					.eq('id', eventId)
					.single()
			);
			expect(row.race_start_mode).toBe('scheduled');
			expect(row.race_scheduled_offset_s).toBe(0);
			expect(row.race_window_length_s).toBe(3 * 3600);
		} finally {
			await ctx.close();
		}
	});

	test('a scheduled race counts down and goes live by itself', async ({ browser }) => {
		const title = `e2e scheduled go ${Date.now()}`;
		const startsAt = new Date(Date.now() + 25_000);
		startsAt.setUTCMilliseconds(0);
		const eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: startsAt.toISOString(),
			timezone: 'UTC',
			race_start_mode: 'scheduled',
			race_scheduled_offset_s: 0,
			race_window_length_s: 3600
		});
		created.push(eventId);

		const ctx = await browser.newContext({ ...ctxOpts, storageState: USER_A.storageStatePath });
		try {
			const page = await ctx.newPage();
			await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
			const panel = page.getByTestId('race-mode-panel');
			await expect(panel).toBeVisible({ timeout: 15_000 });
			await expect(panel).toHaveAttribute('data-race-status', 'armed');
			await expect(page.getByTestId('race-countdown')).toContainText('Starts in');
			await expect(page.getByTestId('race-delay')).toBeVisible();

			// No GO press: the panel turns live on the server clock at the instant.
			await expect(panel).toHaveAttribute('data-race-status', 'running', { timeout: 45_000 });
			await expect(panel).toContainText('Live since');
			await expect(page.getByTestId('race-cancel')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});

	test('a self-timed window offers a member Join and attempt, then sends them to the app', async ({ browser }) => {
		const title = `e2e self-timed ${Date.now()}`;
		const startsAt = new Date(Date.now() - 5 * 60_000);
		startsAt.setUTCSeconds(0, 0);
		const eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: startsAt.toISOString(),
			timezone: 'UTC',
			race_start_mode: 'self_timed',
			race_window_open_offset_s: 0,
			race_window_length_s: 24 * 3600
		});
		created.push(eventId);

		const ctx = await browser.newContext({ ...ctxOpts, storageState: USER_B.storageStatePath });
		try {
			const page = await ctx.newPage();
			await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
			const banner = page.getByTestId('self-timed-banner');
			await expect(banner).toBeVisible({ timeout: 15_000 });
			await expect(banner).toHaveAttribute('data-attempt', 'join');
			await expect(page.getByTestId('race-window-open')).toContainText('Open until');

			await page.getByTestId('self-timed-join').click();
			await expect(banner).toHaveAttribute('data-attempt', 'attempt', { timeout: 10_000 });
			await expect(banner).toContainText('This run is my attempt');

			const rsvp = await readRow(
				'the join RSVP',
				getAdminClient()
					.from('event_attendees')
					.select('status')
					.eq('event_id', eventId)
					.eq('user_id', USER_B.id)
					.single()
			);
			expect(rsvp.status).toBe('going');
		} finally {
			await ctx.close();
		}
	});
});
