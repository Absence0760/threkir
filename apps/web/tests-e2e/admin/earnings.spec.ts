import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Operator platform-fee earnings (/admin/earnings, migration 20270723000002,
 * decisions § 1817).
 *
 * The fee arithmetic and the 42501 boundary are pinned at the DB layer by
 * platform_fee_earnings_test.sql. This spec pins the page on top: the seeded
 * app_admin (USER_A) sees a month row with the fee net of a full refund and
 * can open its host + club breakdown; a signed-in non-admin (USER_B) gets the
 * not-authorized card and no figures.
 *
 * The planted orders sit in March 2019 and in CHF, a month and currency no
 * other spec or seed row uses, so the row is this spec's alone even though
 * the view sums the whole ledger.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const MONTH = '2019-03-01';
const CURRENCY = 'chf';

let eventId: string | null = null;

test.beforeAll(async () => {
	eventId = await insertEvent({
		club_id: RICHMOND_CLUB_ID,
		author_id: USER_A.id,
		title: 'E2E platform fee class',
		category: 'class',
	});
	const admin = getAdminClient();
	const base = {
		event_id: eventId,
		instance_start: '2019-03-20T18:00:00Z',
		buyer_user_id: USER_B.id,
		host_user_id: USER_A.id,
		amount_cents: 2000,
		currency: CURRENCY,
		platform_fee_cents: 100,
	};
	const { error } = await admin.from('event_orders').insert([
		{ ...base, status: 'paid', paid_at: '2019-03-10T12:00:00Z' },
		{ ...base, status: 'refunded', paid_at: '2019-03-11T12:00:00Z' },
	]);
	if (error) throw new Error(`plant orders failed: ${error.message}`);
});

test.afterAll(async () => {
	if (eventId) await deleteEvent(eventId);
});

test.describe('admin earnings — operator view', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a month shows the fee net of a refund, and opens its host breakdown', async ({ page }) => {
		await page.goto('/admin/earnings');

		const row = page.locator(
			`[data-testid="earnings-month-row"][data-month="${MONTH}"][data-currency="${CURRENCY}"]`,
		);
		await expect(row).toBeVisible({ timeout: 15_000 });
		await expect(row).toContainText('March 2019');
		await expect(row.getByTestId('earnings-month-net')).toContainText('1.00');
		await expect(row).toContainText('1 refunded');

		await row.getByTestId('earnings-view-hosts').click();

		const hosts = page.getByTestId('earnings-hosts');
		await expect(hosts.getByRole('heading', { name: /March 2019/ })).toBeFocused();
		const hostRow = hosts.getByTestId('earnings-host-row').filter({ hasText: 'Richmond Run Club' });
		await expect(hostRow).toHaveCount(1);
		await expect(hostRow).toContainText('CHF');
		await expect(hostRow).toContainText('2.00');
	});
});

test.describe('admin earnings — non-admin', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('a signed-in non-admin sees the not-authorized card and no figures', async ({ page }) => {
		await page.goto('/admin/earnings');
		await expect(page.getByTestId('earnings-not-authorized')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('earnings-months')).toHaveCount(0);
	});
});
