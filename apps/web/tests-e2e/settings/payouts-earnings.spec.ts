import { expect, test } from '../fixtures/mock-route';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * /settings/payouts — the host's earnings summary (instructor_business.md M7).
 *
 * The ledger is planted with the service role and read back through the real
 * `host_earnings_summary()` RPC, so what is asserted is the figure the
 * function computed, not a stub's. Two ephemeral hosts keep the shared seed
 * users' payout rows out of it: `event-paid-register.spec.ts` upserts and
 * deletes USER_A's account, and a parallel worker doing that mid-test would
 * hide this section.
 *
 * The class is at 02:00 UTC on 1 November in a Los Angeles event, which is
 * 19:00 on 31 October there: it must be filed under October, the month its
 * attendees were in, whatever zone the browser runs in.
 */
const INSTANCE = '2026-11-01T02:00:00Z';

test.describe.serial('/settings/payouts — earnings summary', () => {
	let host: SagaUser;
	let emptyHost: SagaUser;
	let clubId: string;

	test.beforeAll(async () => {
		[host, emptyHost] = await createSagaUsers(2, {
			displayNames: ['Earnings Host', 'Earnings Empty Host']
		});
		const admin = getAdminClient();
		for (const user of [host, emptyHost]) {
			const { error } = await admin.from('instructor_payout_accounts').insert({
				user_id: user.id,
				stripe_connect_account_id: `acct_e2e_earn_${user.id.slice(0, 8)}`,
				charges_enabled: true,
				payouts_enabled: true,
				details_submitted: true,
				country: 'US',
				default_currency: 'usd'
			});
			if (error) throw error;
		}

		const club = await admin
			.from('clubs')
			.insert({
				owner_id: host.id,
				name: `Earnings Studio ${Date.now()}`,
				slug: `earnings-studio-${Date.now()}`,
				is_public: false
			})
			.select('id')
			.single();
		if (club.error) throw club.error;
		clubId = club.data.id;

		const event = await admin
			.from('events')
			.insert({
				club_id: clubId,
				author_id: host.id,
				host_user_id: host.id,
				title: 'Evening Reformer',
				category: 'class',
				starts_at: INSTANCE,
				timezone: 'America/Los_Angeles'
			})
			.select('id')
			.single();
		if (event.error) throw event.error;

		const order = (status: string, amount: number, fee: number, currency = 'usd') => ({
			event_id: event.data.id,
			instance_start: INSTANCE,
			buyer_user_id: emptyHost.id,
			host_user_id: host.id,
			amount_cents: amount,
			platform_fee_cents: fee,
			currency,
			status,
			paid_at: INSTANCE
		});
		const orders = await admin
			.from('event_orders')
			.insert([
				order('paid', 2000, 100),
				order('paid', 2000, 100),
				order('refunded', 2000, 100),
				order('partially_refunded', 2000, 100),
				order('refund_failed', 2000, 100),
				order('pending', 2000, 100),
				order('paid', 3000, 150, 'eur')
			])
			.select('id, status');
		if (orders.error) throw orders.error;
		const partial = orders.data.find((o) => o.status === 'partially_refunded');
		const refund = await admin.from('payment_refunds').insert({
			stripe_refund_id: `re_e2e_earn_${Date.now()}`,
			event_order_id: partial!.id,
			amount_cents: 500,
			status: 'succeeded'
		});
		if (refund.error) throw refund.error;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (clubId) await admin.from('clubs').delete().eq('id', clubId);
		const users = [host, emptyHost].filter(Boolean);
		if (users.length) {
			await admin
				.from('instructor_payout_accounts')
				.delete()
				.in(
					'user_id',
					users.map((u) => u.id)
				);
			await deleteSagaUsers(users);
		}
	});

	test('a class is filed under the month it ran in its own timezone, one total per currency', async ({
		browser
	}) => {
		const ctx = await browser.newContext({ storageState: host.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/payouts');
			const earnings = page.getByRole('region', { name: 'Earnings' });
			await expect(earnings).toBeVisible({ timeout: 15_000 });

			const usd = earnings.locator('li.month', { hasText: 'October 2026 · USD' });
			await expect(usd).toBeVisible({ timeout: 10_000 });
			// gross 8000 (paid 4000 + partial 2000 + refunded 2000), refunded
			// 2500 (the full refund + the recorded 500), fee 300 (the refunded
			// order's fee went back) -> net 5200. refund_failed is outside it.
			await expect(usd.getByTestId('earnings-net')).toHaveText('$52.00');
			const figure = (label: string) =>
				usd.locator('dl.figures > div', { has: page.getByText(label, { exact: true }) }).locator('dd');
			await expect(figure('Registrations')).toHaveText('3');
			await expect(figure('Gross')).toHaveText('$80.00');
			await expect(figure('Refunded')).toHaveText('$25.00');
			await expect(figure('Platform fee')).toHaveText('$3.00');
			await expect(usd).toContainText('1 refund bounced and is being resolved; $20.00 is left out');

			const eur = earnings.locator('li.month', { hasText: 'October 2026 · EUR' });
			await expect(eur.getByTestId('earnings-net')).toHaveText('€28.50');

			await expect(earnings.getByText(/November 2026/)).toHaveCount(0);

			await usd.getByText('By class (1 class)').click();
			await expect(usd.getByRole('cell', { name: 'Evening Reformer' })).toBeVisible();
		} finally {
			await ctx.close();
		}
	});

	test('a failed read offers a retry instead of claiming there are no earnings', async ({
		browser,
		mockRoute
	}) => {
		const ctx = await browser.newContext({ storageState: host.storageStatePath });
		const page = await ctx.newPage();
		try {
			let fail = true;
			await mockRoute(page, '**/rest/v1/rpc/host_earnings_summary*', async (route) => {
				if (fail) {
					await route.fulfill({
						status: 500,
						contentType: 'application/json',
						body: JSON.stringify({ message: 'boom', code: 'XX000' })
					});
				} else {
					await route.continue();
				}
			});
			await page.goto('/settings/payouts');
			const earnings = page.getByRole('region', { name: 'Earnings' });
			await expect(earnings.getByRole('alert')).toContainText("Couldn't load your earnings.", {
				timeout: 15_000
			});
			await expect(earnings.getByText(/No paid registrations yet/)).toHaveCount(0);

			fail = false;
			await earnings.getByRole('button', { name: 'Try again' }).click();
			await expect(
				earnings.locator('li.month', { hasText: 'October 2026 · USD' }).getByTestId('earnings-net')
			).toHaveText('$52.00', { timeout: 10_000 });
		} finally {
			await ctx.close();
		}
	});

	test('a host who has not been paid yet reads an empty state, not zeroed totals', async ({
		browser
	}) => {
		const ctx = await browser.newContext({ storageState: emptyHost.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/payouts');
			const earnings = page.getByRole('region', { name: 'Earnings' });
			await expect(earnings.getByText(/No paid registrations yet/)).toBeVisible({ timeout: 15_000 });
			await expect(earnings.locator('li.month')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
