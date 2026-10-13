import { expect, test } from '@playwright/test';

import { readRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { clearNotifications, deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * The two event lines the paid rail added to the inbox and the bell:
 *
 *   - an `event_cancel` whose `refunded` column is set (20270725000002) is a
 *     paid registrant's cancel, and must say the payment is being refunded —
 *     while a plain cancel beside it must not promise money it never took;
 *   - an `event_waitlist_slot` (20270726000002, decisions § 1840) tells a
 *     waiter a place is held for them, and opens the event they must pay on.
 *
 * Rows are planted with the service role in the shape the triggers write
 * them (`notify_event_cancel`, `private.fill_event_seats`); the triggers
 * themselves are pgTAP's to pin. What is under test is the copy each surface
 * picks from the row and where the line leads.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const RICHMOND_SLUG = 'richmond-run-club';

test.describe('event notification lines — refunded cancel and waitlist slot', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const created: string[] = [];
	let titles: { refunded: string; plain: string; slot: string };
	let slotEventId: string;

	test.beforeEach(async () => {
		await clearNotifications(USER_A.id);
		const stamp = Date.now();
		titles = {
			refunded: `e2e-paid-cancel ${stamp}`,
			plain: `e2e-free-cancel ${stamp}`,
			slot: `e2e-waitlist-slot ${stamp}`
		};
		const admin = getAdminClient();
		const rows: Record<string, unknown>[] = [];
		for (const [which, title] of Object.entries(titles)) {
			const startsAt = new Date(
				Math.floor((Date.now() + 7 * 24 * 3600 * 1000) / 1000) * 1000
			).toISOString();
			const id = await insertEvent({
				club_id: RICHMOND_CLUB_ID,
				author_id: USER_A.id,
				title,
				category: 'class',
				discipline: 'Reformer pilates',
				starts_at: startsAt
			});
			created.push(id);
			if (which === 'slot') {
				slotEventId = id;
				rows.push({
					user_id: USER_A.id,
					kind: 'event_waitlist_slot',
					event_id: id,
					event_instance_start: startsAt
				});
			} else {
				rows.push({
					user_id: USER_A.id,
					actor_id: USER_B.id,
					kind: 'event_cancel',
					event_id: id,
					event_instance_start: startsAt,
					refunded: which === 'refunded'
				});
			}
		}
		const { error } = await admin.from('notifications').insert(rows);
		if (error) throw new Error(`notification insert failed: ${error.message}`);
	});

	test.afterEach(async () => {
		for (const id of created.splice(0)) {
			try {
				await deleteEvent(id);
			} catch (_) {
				/* best-effort */
			}
		}
		await clearNotifications(USER_A.id);
	});

	test('the inbox says which cancel is being refunded, and the slot opens its event', async ({
		page
	}) => {
		await page.goto(`/u/${USER_A.id}?tab=notifications`);
		const items = page.locator('.item-wrap');
		await expect(items.first()).toBeVisible({ timeout: 10_000 });
		await expect(items).toHaveCount(3);

		await expect(
			items.filter({
				hasText: `An occurrence of "${titles.refunded}" was cancelled — your payment is being refunded`
			})
		).toHaveCount(1);

		const plain = items.filter({ hasText: `An occurrence of "${titles.plain}" was cancelled` });
		await expect(plain.locator('.verb')).toHaveText(`An occurrence of "${titles.plain}" was cancelled`);

		const slot = items.filter({
			hasText: `A place opened in "${titles.slot}" and is held for you — pay to claim it`
		});
		await expect(slot).toHaveCount(1);

		await slot.locator('.item-main').click();
		await expect(page).toHaveURL(new RegExp(`/clubs/${RICHMOND_SLUG}/events/${slotEventId}$`), {
			timeout: 10_000
		});
		await expect(page.getByRole('heading', { name: titles.slot })).toBeVisible({ timeout: 10_000 });
		await expect
			.poll(async () => {
				const row = await readRow(
					'waitlist slot notification',
					getAdminClient()
						.from('notifications')
						.select('read_at')
						.eq('user_id', USER_A.id)
						.eq('kind', 'event_waitlist_slot')
						.single()
				);
				return row.read_at !== null;
			})
			.toBe(true);
	});

	test('the bell carries the same refunded and waitlist-slot lines', async ({ page }) => {
		await page.goto('/dashboard');
		await expect(page.locator('.bell-wrap .badge')).toHaveText('3', { timeout: 10_000 });

		await page.locator('.bell-wrap .bell-btn').click();
		const popover = page.locator('.bell-wrap [role="dialog"]');
		await expect(popover).toBeVisible({ timeout: 5_000 });
		await expect(popover).toContainText(
			`An occurrence of "${titles.refunded}" was cancelled — your payment is being refunded`
		);
		await expect(popover).toContainText(
			`A place opened in "${titles.slot}" and is held for you — pay to claim it`
		);
		await expect(popover.locator('.verb').filter({ hasText: titles.plain })).toHaveText(
			`An occurrence of "${titles.plain}" was cancelled`
		);
	});
});
