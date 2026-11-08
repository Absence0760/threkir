import { expect, test } from '../fixtures/test';

import { acceptCookieConsent } from '../fixtures/helpers';
import { noonOnBrowserDay } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { deleteEvent, insertEvent, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /dashboard's Today block shows the runner's next `going` club event when it
 * starts within the next 48 hours, the Run tab's window (decisions § 2388,
 * issue #1187). § 2285 had widened it to seven days; the owner kept 48 hours
 * on both platforms, because an event days away is not "today".
 *
 * A fresh saga user keeps the read honest: the card shows only the EARLIEST
 * going RSVP, so a shared seeded account's RSVPs from other specs could
 * otherwise stand in front of this one.
 */

const CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const DAY_MS = 24 * 3600 * 1000;

test.describe('/dashboard — next club event within 48 hours', () => {
	test.describe.configure({ mode: 'serial' });

	let user: SagaUser;
	const eventIds: string[] = [];

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Upcoming Event Runner'] });
		await insertRun({
			user_id: user.id,
			started_at: noonOnBrowserDay(-1),
			distance_m: 5_000,
			duration_s: 1_650,
		});
		const { error } = await getAdminClient()
			.from('club_members')
			.upsert(
				{ club_id: CLUB_ID, user_id: user.id, role: 'member', status: 'active' },
				{ onConflict: 'club_id,user_id' },
			);
		if (error) throw new Error(`club_members upsert failed: ${error.message}`);
	});

	test.afterAll(async () => {
		for (const id of eventIds) {
			try {
				await deleteEvent(id);
			} catch (_) {
				/* attendees cascade on event delete */
			}
		}
		if (user) {
			await getAdminClient().from('club_members').delete().eq('club_id', CLUB_ID).eq('user_id', user.id);
			await deleteSagaUsers([user]);
		}
	});

	async function goingTo(title: string, startsInMs: number): Promise<void> {
		const startsAt = new Date(Date.now() + startsInMs).toISOString();
		const id = await insertEvent({ club_id: CLUB_ID, author_id: USER_A.id, title, starts_at: startsAt });
		eventIds.push(id);
		const admin = getAdminClient();
		const { data: ev, error: evErr } = await admin.from('events').select('starts_at').eq('id', id).single();
		if (evErr || !ev) throw new Error(`event read failed: ${evErr?.message ?? 'no row'}`);
		const { error } = await admin
			.from('event_attendees')
			.insert({ event_id: id, user_id: user.id, instance_start: ev.starts_at, status: 'going' });
		if (error) throw new Error(`event_attendees insert failed: ${error.message}`);
	}

	test('an event four days out is not on Home yet', async ({ browser }) => {
		const title = `e2e-upcoming-far ${Date.now()}`;
		await goingTo(title, 4 * DAY_MS);
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');
			await expect(page.getByTestId('dash-week-lead')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('dash-upcoming-event')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});

	test('an event twenty hours out is in the Today block, above Trends', async ({ browser }) => {
		const title = `e2e-upcoming-near ${Date.now()}`;
		await goingTo(title, 20 * 3600 * 1000);
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');
			const card = page.getByTestId('dash-upcoming-event');
			await expect(card).toBeVisible({ timeout: 15_000 });
			await expect(card).toContainText(title);
			const cardBox = await card.boundingBox();
			const dividerBox = await page.getByTestId('dash-trends-divider').boundingBox();
			expect(cardBox && dividerBox && cardBox.y < dividerBox.y).toBe(true);
		} finally {
			await ctx.close();
		}
	});
});
