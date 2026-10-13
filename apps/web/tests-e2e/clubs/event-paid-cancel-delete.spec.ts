import { expect, test } from '@playwright/test';

import { readMaybeRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Calling off a class that took payments, from the organiser's side
 * (club_events.md § Refunds & cancellation coupling, decisions § 1867 and
 * § 1868):
 *   (a) Delete on an event that took a payment is refused by
 *       `guard_paid_event_delete`, the page says why, and the event and its
 *       order are still there;
 *   (b) a one-off paid class offers Cancel event, says everyone is refunded,
 *       and fails closed when payments are unavailable;
 *   (c) a free one-off cancels in place and can be reinstated;
 *   (d) a free series cancels whole: the series ends, the occurrence someone
 *       RSVP'd to is called off by name, and the page says the series was
 *       cancelled;
 *   (e) a paid series is not ended while it cannot be refunded.
 * The live refunds need operator sk_test_ keys; without one the function
 * answers 503 `stripe_not_configured`, which is what (b) and (e) pin.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const RICHMOND_SLUG = 'richmond-run-club';
const WEEK_MS = 7 * 24 * 3600 * 1000;

/// Whole seconds: `expandInstances` stamps each occurrence with a zero
/// millisecond, so a sub-second start drops its own first occurrence.
function weeksOut(n: number): string {
	return new Date(Math.floor((Date.now() + n * WEEK_MS) / 1000) * 1000).toISOString();
}

async function priceEvent(eventId: string): Promise<() => Promise<void>> {
	const admin = getAdminClient();
	await admin.from('instructor_payout_accounts').upsert({
		user_id: USER_A.id,
		stripe_connect_account_id: `acct_e2e_${USER_A.id.slice(0, 8)}`,
		charges_enabled: true,
		payouts_enabled: true,
		details_submitted: true,
		country: 'US',
		default_currency: 'usd'
	});
	const { error } = await admin.from('event_pricing').insert({
		event_id: eventId,
		instance_start: null,
		price_cents: 2200,
		currency: 'usd',
		modality: 'in_person',
		refund_policy: 'no_refund',
		sales_close_offset_minutes: 0
	});
	if (error) throw new Error(`priceEvent failed: ${error.message}`);
	return async () => {
		await admin.from('event_pricing').delete().eq('event_id', eventId);
		await admin.from('instructor_payout_accounts').delete().eq('user_id', USER_A.id);
	};
}

async function insertPaidOrder(eventId: string, instanceStart: string): Promise<void> {
	const now = new Date().toISOString();
	const { error } = await getAdminClient()
		.from('event_orders')
		.insert({
			event_id: eventId,
			instance_start: instanceStart,
			buyer_user_id: USER_B.id,
			host_user_id: USER_A.id,
			stripe_payment_intent_id: `pi_e2e_pcd_${Date.now()}`,
			amount_cents: 2200,
			currency: 'usd',
			platform_fee_cents: 55,
			status: 'paid',
			paid_at: now
		});
	if (error) throw new Error(`order insert failed: ${error.message}`);
}

test.describe('organiser cancels or deletes a paid class', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const created: string[] = [];
	const cleanups: (() => Promise<void>)[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const fn of cleanups.splice(0)) {
			try {
				await fn();
			} catch (_) {
				/* best-effort */
			}
		}
		for (const id of created.splice(0)) {
			try {
				await admin.from('event_orders').delete().eq('event_id', id);
				await deleteEvent(id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	async function classEvent(
		title: string,
		startsAt: string,
		recurring: boolean,
		priced: boolean
	): Promise<string> {
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
			discipline: 'Reformer pilates',
			capacity: 10,
			starts_at: startsAt,
			recurrence_freq: recurring ? 'weekly' : null
		});
		created.push(id);
		if (priced) cleanups.push(await priceEvent(id));
		return id;
	}

	test('deleting an event that took a payment is refused and nothing is erased', async ({ page }) => {
		const admin = getAdminClient();
		const title = `e2e-paid-delete ${Date.now()}`;
		const startsAt = weeksOut(1);
		const id = await classEvent(title, startsAt, false, true);
		await insertPaidOrder(id, startsAt);

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});
		await page.getByRole('button', { name: 'Delete event' }).click();
		const dialog = page.locator('.modal', { hasText: 'Delete event' });
		await dialog.getByRole('button', { name: 'Delete', exact: true }).click();

		await expect(page.getByText(/has taken payments, so it can't be deleted/i)).toBeVisible({
			timeout: 10_000
		});
		await expect(page).toHaveURL(new RegExp(`/events/${id}$`));

		const event = await readMaybeRow(
			'events by id',
			admin.from('events').select('id').eq('id', id).maybeSingle()
		);
		expect(event).toEqual({ id });
		const orders = await readRows(
			'event_orders by event_id',
			admin.from('event_orders').select('status').eq('event_id', id)
		);
		expect(orders).toEqual([{ status: 'paid' }]);
	});

	test('a one-off paid class offers Cancel event and is not called off while it cannot be refunded', async ({
		page
	}) => {
		const admin = getAdminClient();
		const title = `e2e-oneoff-paid-cancel ${Date.now()}`;
		const startsAt = weeksOut(1);
		const id = await classEvent(title, startsAt, false, true);
		await insertPaidOrder(id, startsAt);

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});
		// A one-off has no series to cancel.
		await expect(page.getByTestId('cancel-series')).toHaveCount(0);

		await page.getByTestId('cancel-occurrence').click();
		const dialog = page.getByRole('dialog');
		await expect(dialog.getByTestId('cancel-instance-refund-note')).toContainText(
			/refunded in full/i
		);
		await dialog.getByRole('button', { name: 'Cancel event' }).click();

		await expect(
			page.getByText(/This event has paid registrations and payments aren't available right now/i)
		).toBeVisible({ timeout: 10_000 });

		// Positive control: the same read sees the order, so an empty exception
		// list is a refusal, not a blind read.
		const orders = await readRows(
			'event_orders by event_id',
			admin.from('event_orders').select('status').eq('event_id', id)
		);
		expect(orders).toEqual([{ status: 'paid' }]);
		const exceptions = await readRows(
			'event_exceptions by event_id',
			admin.from('event_exceptions').select('instance_start').eq('event_id', id)
		);
		expect(exceptions).toHaveLength(0);
	});

	test('a free one-off cancels in place and can be reinstated', async ({ page }) => {
		const title = `e2e-oneoff-free-cancel ${Date.now()}`;
		const id = await classEvent(title, weeksOut(1), false, false);

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});
		await page.getByTestId('cancel-occurrence').click();
		await page.getByRole('dialog').getByRole('button', { name: 'Cancel event' }).click();

		await expect(page.getByText('This event was cancelled.')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('cancel-occurrence')).toHaveCount(0);
		await page.getByRole('button', { name: 'Reinstate this event' }).click();
		await expect(page.getByText('This event was cancelled.')).toHaveCount(0, { timeout: 10_000 });
		await expect(page.getByTestId('cancel-occurrence')).toBeVisible();
	});

	test('a free series cancels whole: it ends, and the occurrence someone RSVPd to is called off', async ({
		page
	}) => {
		const admin = getAdminClient();
		const title = `e2e-series-cancel ${Date.now()}`;
		const firstStart = weeksOut(1);
		const id = await classEvent(title, firstStart, true, false);
		const rsvpStart = weeksOut(2);
		const { error } = await admin.from('event_attendees').insert({
			event_id: id,
			user_id: USER_B.id,
			instance_start: rsvpStart,
			status: 'going'
		});
		if (error) throw new Error(`rsvp insert failed: ${error.message}`);

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});
		await page.getByTestId('cancel-series').click();
		const dialog = page.getByRole('dialog');
		await expect(dialog.getByTestId('cancel-series-refund-note')).toHaveCount(0);
		await dialog.getByRole('button', { name: 'Cancel the whole series' }).click();

		await expect(page.getByText('Series cancelled.')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('series-cancelled')).toBeVisible();
		await expect(page.getByTestId('cancel-series')).toHaveCount(0);

		const event = await readMaybeRow(
			'events by id',
			admin.from('events').select('recurrence_until').eq('id', id).maybeSingle()
		);
		expect(event?.recurrence_until).not.toBeNull();
		expect(Date.parse(event!.recurrence_until!)).toBeLessThan(Date.parse(firstStart));
		const exceptions = await readRows(
			'event_exceptions by event_id',
			admin.from('event_exceptions').select('instance_start').eq('event_id', id)
		);
		expect(exceptions.map((e) => Date.parse(e.instance_start))).toEqual([Date.parse(rsvpStart)]);
	});

	test('a paid series is not ended while it cannot be refunded', async ({ page }) => {
		const admin = getAdminClient();
		const title = `e2e-series-paid-cancel ${Date.now()}`;
		const startsAt = weeksOut(1);
		const id = await classEvent(title, startsAt, true, true);
		await insertPaidOrder(id, startsAt);

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});
		await page.getByTestId('cancel-series').click();
		const dialog = page.getByRole('dialog');
		await expect(dialog.getByTestId('cancel-series-refund-note')).toContainText(/refunded in full/i);
		await dialog.getByRole('button', { name: 'Cancel the whole series' }).click();

		await expect(
			page.getByText(/This series has paid registrations and payments aren't available right now/i)
		).toBeVisible({ timeout: 10_000 });

		const event = await readMaybeRow(
			'events by id',
			admin.from('events').select('recurrence_until').eq('id', id).maybeSingle()
		);
		expect(event).toEqual({ recurrence_until: null });
		const exceptions = await readRows(
			'event_exceptions by event_id',
			admin.from('event_exceptions').select('instance_start').eq('event_id', id)
		);
		expect(exceptions).toHaveLength(0);
	});
});
