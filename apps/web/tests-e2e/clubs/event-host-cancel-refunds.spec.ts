import { expect, test } from '@playwright/test';

import { readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * A host cancelling a paid occurrence refunds every registrant (M8,
 * club_events.md § Refunds, decisions § 1818) — the organiser UI.
 *
 * The live Stripe round-trip (events-cancel `scope: 'occurrence'` creates each
 * refund, charge.refunded flips the orders) needs operator sk_test_ keys. With
 * none configured the function answers 503 `stripe_not_configured`, and what
 * this spec pins is everything reachable without one:
 *   (a) the cancel dialog on a priced class says everyone will be refunded;
 *   (b) a paid occurrence is NOT called off when it cannot be refunded — the
 *       direct insert is refused by `guard_paid_occurrence_cancel`, the page
 *       hands it to the function, the function fails closed, and the organiser
 *       is told so with the occurrence and the order untouched;
 *   (c) a cancelled occurrence that still owes money says so on a fresh load,
 *       naming what is owed, in flight and sent back, and offers Refund now,
 *       which fails closed to an error toast rather than a false success;
 *   (d) a cancelled occurrence whose orders are all settled shows no panel.
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

async function insertOrder(
	eventId: string,
	instanceStart: string,
	buyerId: string,
	status: 'paid' | 'refund_failed' | 'refunded',
	refundInitiated: boolean
): Promise<void> {
	const now = new Date().toISOString();
	const { error } = await getAdminClient()
		.from('event_orders')
		.insert({
			event_id: eventId,
			instance_start: instanceStart,
			buyer_user_id: buyerId,
			host_user_id: USER_A.id,
			stripe_payment_intent_id: `pi_e2e_hc_${buyerId.slice(0, 6)}_${Date.now()}`,
			amount_cents: 2200,
			currency: 'usd',
			platform_fee_cents: 55,
			status,
			paid_at: now,
			refunded_at: status === 'paid' ? null : now,
			refund_initiated_at: refundInitiated ? now : null
		});
	if (error) throw new Error(`order insert failed: ${error.message}`);
}

/// The cancel the events-cancel function records, written the way it writes
/// it: as the service role, which is the only role the guard lets cancel an
/// occurrence that still holds money.
async function cancelAsService(eventId: string, instanceStart: string): Promise<void> {
	const { error } = await getAdminClient().from('event_exceptions').insert({
		event_id: eventId,
		instance_start: instanceStart,
		cancelled_by: USER_A.id,
		reason: 'Studio flooded'
	});
	if (error) throw new Error(`exception insert failed: ${error.message}`);
}

test.describe('host cancels a paid occurrence (M8)', () => {
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

	async function pricedClass(title: string, startsAt: string): Promise<string> {
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
			discipline: 'Reformer pilates',
			capacity: 10,
			starts_at: startsAt,
			recurrence_freq: 'weekly'
		});
		created.push(id);
		cleanups.push(await priceEvent(id));
		return id;
	}

	test('a paid occurrence is not called off while it cannot be refunded', async ({ page }) => {
		const admin = getAdminClient();
		const title = `e2e-hostcancel ${Date.now()}`;
		const startsAt = weeksOut(1);
		const id = await pricedClass(title, startsAt);
		await insertOrder(id, startsAt, USER_B.id, 'paid', false);

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Cancel this occurrence' }).click();
		const dialog = page.getByRole('dialog');
		// The policy on this class is no_refund; the host cancelling overrides it.
		await expect(dialog.getByTestId('cancel-instance-refund-note')).toContainText(
			/refunded in full/i
		);
		await dialog.getByRole('button', { name: 'Cancel this occurrence' }).click();

		await expect(page.getByText(/payments aren't available right now/i)).toBeVisible({
			timeout: 10_000
		});

		// Nothing changed: no exception row, and the order still holds the money.
		// Positive control for the empty read below: the same query shape sees
		// the order, so an empty exception list is a refusal, not a blind read.
		const orders = await readRows(
			'event_orders by event_id',
			admin.from('event_orders').select('status, refund_initiated_at').eq('event_id', id)
		);
		expect(orders).toEqual([{ status: 'paid', refund_initiated_at: null }]);
		const exceptions = await readRows(
			'event_exceptions by event_id',
			admin.from('event_exceptions').select('instance_start').eq('event_id', id)
		);
		expect(exceptions).toHaveLength(0);
	});

	test('a cancelled occurrence that still owes money says so, and Refund now fails closed', async ({
		page
	}) => {
		const title = `e2e-hostcancel-owed ${Date.now()}`;
		const startsAt = weeksOut(1);
		const id = await pricedClass(title, startsAt);
		await insertOrder(id, startsAt, USER_B.id, 'paid', false);
		await insertOrder(id, startsAt, USER_C_PRO.id, 'paid', true);
		await insertOrder(id, startsAt, USER_A.id, 'refund_failed', true);
		await cancelAsService(id, startsAt);

		// A fresh load lands on the next LIVE occurrence; the debt on the
		// cancelled one is still in front of the organiser.
		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		const panel = page.getByTestId('occurrence-refunds');
		await expect(panel).toBeVisible();
		await expect(panel).toContainText("1 registrant hasn't been refunded yet.");
		await expect(panel).toContainText('1 refund is in progress.');
		await expect(panel).toContainText('1 refund was sent back by the bank');

		await panel.getByTestId('occurrence-refunds-retry').click();
		await expect(page.getByText(/payments aren't available right now/i)).toBeVisible({
			timeout: 10_000
		});
		// Still owed: the failure did not clear the panel.
		await expect(panel).toContainText("1 registrant hasn't been refunded yet.");
	});

	test('a cancelled occurrence with every order settled shows no refund panel', async ({ page }) => {
		const title = `e2e-hostcancel-settled ${Date.now()}`;
		const startsAt = weeksOut(1);
		const id = await pricedClass(title, startsAt);
		await insertOrder(id, startsAt, USER_B.id, 'refunded', true);
		await cancelAsService(id, startsAt);

		await page.goto(`/clubs/${RICHMOND_SLUG}/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		// Positive control first: the page knows about the cancelled occurrence.
		await expect(page.getByTestId('cancelled-occurrences')).toBeVisible();
		await expect(page.getByTestId('occurrence-refunds')).toHaveCount(0);
	});
});
