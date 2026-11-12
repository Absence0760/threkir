import { expect, test } from '../fixtures/test';

import { readCount, readMaybeRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * The unpaid waitlist on a PAID occurrence (migration 20270726000002,
 * decisions § 1840) — what the viewer's own place reads as on the event page.
 *
 * A sold-out priced occurrence offers "Join the waitlist"; joining writes a
 * `waitlisted` row with no order. When a seat frees, the earliest waiter is
 * OFFERED it until `offer_expires_at` rather than seated, and Register becomes
 * "Claim your place". Every state below is planted with the service role
 * (the offer column is not client-writable) except the join and the leave,
 * which are driven through the page. Claiming goes through `events-checkout`,
 * stubbed here: the live charge needs operator Stripe keys, and what is under
 * test is that the claim CTA asks for THIS occurrence.
 *
 *   (a) join: Sold out + Join the waitlist; the click lands an order-less row;
 *   (b) waiting: queued, no offer — Leave the waitlist, no claim;
 *   (c) offered: the held-until line names the deadline and Claim carries the
 *       price, and pressing it starts checkout for the occurrence;
 *   (d) lapsed: a passed deadline promises nothing — no held line, no claim;
 *   (e) leave asks first: Cancel keeps the place, confirming removes it;
 *   (f) sales closed: a sold-out occurrence nobody can pay for any more offers
 *       no waitlist to join.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const RICHMOND_SLUG = 'richmond-run-club';
const HOUR_MS = 3600 * 1000;

/// Whole seconds, so the attendee rows planted below name exactly the
/// instant the page resolves as the occurrence.
function hoursOut(n: number): string {
	return new Date(Math.floor((Date.now() + n * HOUR_MS) / 1000) * 1000).toISOString();
}

async function priceEvent(
	eventId: string,
	salesCloseOffset = 0
): Promise<() => Promise<void>> {
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
		refund_policy: 'full_until_24h',
		sales_close_offset_minutes: salesCloseOffset
	});
	if (error) throw new Error(`priceEvent failed: ${error.message}`);
	return async () => {
		await admin.from('event_pricing').delete().eq('event_id', eventId);
		await admin.from('instructor_payout_accounts').delete().eq('user_id', USER_A.id);
	};
}

/// Fill the occurrence's one seat with USER_B: a paid order and the going row
/// the webhook would have written for it.
async function fillTheSeat(eventId: string, instanceStart: string): Promise<void> {
	const admin = getAdminClient();
	const { data: order, error: orderErr } = await admin
		.from('event_orders')
		.insert({
			event_id: eventId,
			instance_start: instanceStart,
			buyer_user_id: USER_B.id,
			host_user_id: USER_A.id,
			stripe_payment_intent_id: `pi_e2e_wl_${eventId.slice(0, 8)}`,
			amount_cents: 2200,
			currency: 'usd',
			platform_fee_cents: 110,
			status: 'paid',
			paid_at: new Date().toISOString()
		})
		.select('id')
		.single();
	if (orderErr || !order) throw new Error(`fillTheSeat order insert failed: ${orderErr?.message}`);
	const { error } = await admin.from('event_attendees').upsert({
		event_id: eventId,
		user_id: USER_B.id,
		instance_start: instanceStart,
		status: 'going',
		order_id: (order as { id: string }).id
	});
	if (error) throw new Error(`fillTheSeat attendee upsert failed: ${error.message}`);
}

/// The viewer's own waitlist row, as the join or the seat mover leaves it.
async function placeViewer(
	eventId: string,
	instanceStart: string,
	offerExpiresAt: string | null
): Promise<void> {
	const { error } = await getAdminClient().from('event_attendees').upsert({
		event_id: eventId,
		user_id: USER_A.id,
		instance_start: instanceStart,
		status: 'waitlisted',
		offer_expires_at: offerExpiresAt
	});
	if (error) throw new Error(`placeViewer upsert failed: ${error.message}`);
}

function viewerRows(eventId: string) {
	return getAdminClient()
		.from('event_attendees')
		.select('status, order_id, offer_expires_at', { count: 'exact' })
		.eq('event_id', eventId)
		.eq('user_id', USER_A.id);
}

test.describe('paid occurrence waitlist — join, wait, offer, claim, leave', () => {
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

	/// A priced class of capacity 1 whose seat USER_B already holds.
	async function soldOutClass(
		label: string,
		opts: { startsAt?: string; salesCloseOffset?: number } = {}
	): Promise<{ id: string; title: string; instanceStart: string }> {
		const title = `e2e-waitlist-${label} ${Date.now()}`;
		const instanceStart = opts.startsAt ?? hoursOut(7 * 24);
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
			discipline: 'Reformer pilates',
			capacity: 1,
			starts_at: instanceStart
		});
		created.push(id);
		cleanups.push(await priceEvent(id, opts.salesCloseOffset ?? 0));
		await fillTheSeat(id, instanceStart);
		return { id, title, instanceStart };
	}

	async function open(page: import('@playwright/test').Page, id: string, title: string) {
		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('register-box')).toBeVisible();
	}

	test('a sold-out occurrence offers the waitlist, and joining lands a row with no order', async ({
		page
	}) => {
		const { id, title } = await soldOutClass('join');
		await open(page, id, title);

		const box = page.getByTestId('register-box');
		await expect(box.getByText('Sold out')).toBeVisible();
		await expect(page.getByTestId('register-cta')).toHaveCount(0);
		const join = page.getByTestId('join-waitlist');
		await expect(join).toHaveText('Join the waitlist');

		await join.click();
		await expect(page.getByTestId('waitlist-waiting')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('join-waitlist')).toHaveCount(0);
		await expect(page.getByTestId('leave-waitlist')).toBeVisible();

		const row = await readMaybeRow('viewer waitlist row', viewerRows(id).maybeSingle());
		expect(row?.status).toBe('waitlisted');
		expect(row?.order_id, 'a waitlist place on a priced occurrence holds no money').toBeNull();
		expect(row?.offer_expires_at, 'joining offers nothing by itself').toBeNull();
	});

	test('a queued place with no offer reads as waiting and offers no claim', async ({ page }) => {
		const { id, title, instanceStart } = await soldOutClass('waiting');
		await placeViewer(id, instanceStart, null);
		await open(page, id, title);

		await expect(page.getByTestId('waitlist-waiting')).toContainText("You're on the waitlist");
		await expect(page.getByTestId('leave-waitlist')).toBeVisible();
		await expect(page.getByTestId('waitlist-offer')).toHaveCount(0);
		await expect(page.getByTestId('claim-cta')).toHaveCount(0);
		await expect(page.getByTestId('join-waitlist')).toHaveCount(0);
	});

	test('an offer names its deadline and the claim starts checkout for this occurrence', async ({
		page,
		mockRoute
	}) => {
		const { id, title, instanceStart } = await soldOutClass('offer');
		await placeViewer(id, instanceStart, hoursOut(6));

		const checkout: { body: { event_id?: string; instance_start?: string } | null } = { body: null };
		await mockRoute(page, '**/functions/v1/events-checkout', async (route, request) => {
			checkout.body = request.postDataJSON();
			await route.fulfill({
				status: 503,
				contentType: 'application/json',
				body: JSON.stringify({ error: 'stripe_not_configured' })
			});
		});

		await open(page, id, title);

		const offer = page.getByTestId('waitlist-offer');
		await expect(offer).toContainText('A place is held for you until');
		await expect(offer).toContainText('the next person on the waitlist');
		const claim = page.getByTestId('claim-cta');
		await expect(claim).toContainText('Claim your place');
		await expect(claim).toContainText('22');
		// The held seat is the viewer's own, so the sold-out branch and the
		// waitlist buttons beneath it never draw.
		await expect(page.getByTestId('waitlist-waiting')).toHaveCount(0);
		await expect(page.getByTestId('join-waitlist')).toHaveCount(0);

		await claim.click();
		await expect(
			page.getByText("The host can't take payments for this event right now", { exact: false })
		).toBeVisible({ timeout: 10_000 });
		expect(checkout.body?.event_id).toBe(id);
		expect(Date.parse(checkout.body?.instance_start ?? '')).toBe(Date.parse(instanceStart));
		await expect(page).toHaveURL(new RegExp(`/clubs/${RICHMOND_SLUG}/events/${id}`));
	});

	test('a lapsed offer promises nothing: no held line and no claim', async ({ page }) => {
		const { id, title, instanceStart } = await soldOutClass('lapsed');
		// The expiry mover runs every 5 minutes, so the row may or may not
		// still be there when the page loads; neither shape may promise a seat.
		await placeViewer(id, instanceStart, new Date(Date.now() - 60_000).toISOString());
		await open(page, id, title);

		await expect(page.getByTestId('register-box').getByText('Sold out')).toBeVisible();
		await expect(page.getByTestId('waitlist-offer')).toHaveCount(0);
		await expect(page.getByTestId('claim-cta')).toHaveCount(0);
		await expect(page.getByTestId('register-cta')).toHaveCount(0);
		await expect(page.getByTestId('waitlist-waiting')).toHaveCount(0);
	});

	test('leaving asks first: Cancel keeps the place, confirming gives it up', async ({ page }) => {
		const { id, title, instanceStart } = await soldOutClass('leave');
		await placeViewer(id, instanceStart, null);
		await open(page, id, title);

		await page.getByTestId('leave-waitlist').click();
		const dialog = page.getByTestId('leave-waitlist-dialog');
		await expect(dialog).toBeVisible();
		await expect(dialog).toContainText('Leave the waitlist?');
		await expect(dialog).toContainText('you go to the back');

		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(dialog).toHaveCount(0);
		await expect(page.getByTestId('waitlist-waiting')).toBeVisible();
		expect(await readCount('viewer row kept', viewerRows(id))).toBe(1);

		await page.getByTestId('leave-waitlist').click();
		await expect(dialog).toBeVisible();
		await dialog.getByRole('button', { name: 'Leave the waitlist' }).click();
		await expect(dialog).toHaveCount(0, { timeout: 10_000 });
		await expect(page.getByTestId('join-waitlist')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('waitlist-waiting')).toHaveCount(0);
		await expect.poll(() => readCount('viewer row removed', viewerRows(id))).toBe(0);
	});

	test('a sold-out occurrence past sales close offers no waitlist to join', async ({ page }) => {
		// Starts in 30 minutes with a 60-minute sales-close offset, so nobody
		// can pay for it any more — a queue for it would promise nothing.
		const { id, title } = await soldOutClass('closed', {
			startsAt: new Date(Math.floor((Date.now() + 30 * 60 * 1000) / 1000) * 1000).toISOString(),
			salesCloseOffset: 60
		});
		await open(page, id, title);

		await expect(page.getByTestId('register-box').getByText('Sold out')).toBeVisible();
		await expect(page.getByTestId('join-waitlist')).toHaveCount(0);
		await expect(page.getByTestId('register-cta')).toHaveCount(0);
		await expect(page.getByTestId('claim-cta')).toHaveCount(0);
	});
});
