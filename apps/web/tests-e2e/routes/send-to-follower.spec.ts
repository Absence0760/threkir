import { expect, test } from '../fixtures/mock-route';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';
import { readRow, readRows } from '../fixtures/db-read';

/**
 * /routes/[id] — in-app "Send a route to a follower" (route_direct_share.md).
 *
 * The send still puts the public /share/route/[id] URL in the DM body — it is
 * the forwardable artifact the dialog's copy promises the recipient gets, and
 * the only thing the inbox preview line and the Art 20 export read. Since v2
 * (migration 20270619_001) it ALSO carries a typed route_id, and the thread
 * draws that as a card; what the card renders, and what a recipient who cannot
 * see the route gets instead, is pinned by messages/dm-route-attachment.spec.ts.
 *
 * Seed follow graph, which the picker's union is built on:
 *   USER_A <-> USER_B (Alex Chen)   mutual
 *   USER_A  -> USER_C (Morgan Lee)  one-way; Morgan does not follow back
 * Both are DM-eligible under the direct_messages INSERT policy, which admits a
 * follow edge in either direction.
 */

const SHARE_PATH = `/share/route/${RUNNER_PUBLIC_ROUTE_ID}`;

async function clearSentDms() {
	await getAdminClient().from('direct_messages').delete().eq('sender_id', USER_A.id);
	await getAdminClient().from('route_shares').delete().eq('route_id', RUNNER_PUBLIC_ROUTE_ID);
}

test.describe('/routes/[id] — send to a follower', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		await getAdminClient()
			.from('routes')
			.update({ is_public: true })
			.eq('id', RUNNER_PUBLIC_ROUTE_ID);
		await clearSentDms();
	});

	test.afterEach(async () => {
		await clearSentDms();
	});

	test('sends the share link as a DM and the recipient opens it in their thread', async ({
		page,
		browser
	}) => {
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.getByTestId('route-send-dm-btn').click();

		const dialog = page.getByTestId('send-route-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });

		// The union of both follow directions, name-ordered.
		await expect(dialog.getByRole('button', { name: /Alex Chen/ })).toBeVisible({
			timeout: 10_000
		});
		await dialog.getByRole('button', { name: /Alex Chen/ }).click();

		await expect(page.getByTestId('send-route-sent')).toContainText('Alex Chen');

		// The row that actually landed carries the public share URL as its body.
		const data = await readRows(
			'direct_messages by sender_id',
			getAdminClient()
				.from('direct_messages')
				.select('body, recipient_id')
				.eq('sender_id', USER_A.id)
		);
		expect(data).toHaveLength(1);
		expect(data[0].recipient_id).toBe(USER_B.id);
		expect(data[0].body).toContain(SHARE_PATH);

		// And the recipient can open it from their own conversation. The bubble
		// renders the typed attachment as a card rather than the URL, so the
		// route is reached through the card's own link.
		const recipient = await browser.newContext({ storageState: USER_B.storageStatePath });
		try {
			const recipientPage = await recipient.newPage();
			await recipientPage.goto(`/messages/${USER_A.id}`);
			const card = recipientPage.getByTestId('dm-route-attachment');
			await expect(card).toBeVisible({ timeout: 15_000 });
			await expect(card).toHaveAttribute('href', `/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		} finally {
			await recipient.close();
		}
	});

	test('offers a runner the sender follows who does not follow back', async ({ page }) => {
		// The picker is the DM-eligible set, not the follower list: Morgan follows
		// nobody, so a followers-only picker would hide a send RLS accepts.
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.getByTestId('route-send-dm-btn').click();

		const dialog = page.getByTestId('send-route-dialog');
		await dialog.getByTestId('send-route-search').fill('morgan');
		await expect(dialog.getByRole('button', { name: /Morgan Lee/ })).toBeVisible({
			timeout: 10_000
		});
		await expect(dialog.getByRole('button', { name: /Alex Chen/ })).toHaveCount(0);

		await dialog.getByRole('button', { name: /Morgan Lee/ }).click();
		await expect(page.getByTestId('send-route-sent')).toContainText('Morgan Lee');

		const data = await readRows(
			'direct_messages by sender_id',
			getAdminClient()
				.from('direct_messages')
				.select('recipient_id')
				.eq('sender_id', USER_A.id)
		);
		expect(data[0].recipient_id).toBe(USER_C_PRO.id);
	});

	test('a private route is shared with the recipient instead of being flipped public', async ({ page }) => {
		// Sending to one person must not widen the route's exposure. With
		// audience sharing on (the seed opens it), the send grants that one
		// person access and carries the in-app link; the route stays private
		// and no public-flip confirm appears (decisions § R7SHARE-1).
		const admin = getAdminClient();
		await admin.from('routes').update({ is_public: false }).eq('id', RUNNER_PUBLIC_ROUTE_ID);

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');

		await page.getByTestId('route-send-dm-btn').click();
		await expect(page.locator('[data-testid="share-confirm-dialog"]')).toBeHidden();
		const dialog = page.getByTestId('send-route-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await expect(dialog.getByTestId('send-route-note')).toContainText('It stays private');

		await dialog.getByRole('button', { name: /Alex Chen/ }).click();
		await expect(page.getByTestId('send-route-sent')).toContainText('Alex Chen');

		const route = await readRow(
			'routes by id',
			admin.from('routes').select('is_public').eq('id', RUNNER_PUBLIC_ROUTE_ID).single()
		);
		expect(route.is_public).toBe(false);
		const grants = await readRows(
			'route_shares by route_id',
			admin.from('route_shares').select('recipient_id').eq('route_id', RUNNER_PUBLIC_ROUTE_ID)
		);
		expect(grants).toEqual([{ recipient_id: USER_B.id }]);
		const sent = await readRows(
			'direct_messages by sender_id',
			admin.from('direct_messages').select('body').eq('sender_id', USER_A.id)
		);
		expect(sent[0].body).toContain(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		expect(sent[0].body).not.toContain(SHARE_PATH);
	});

	test('a failed recipient load surfaces a retry, not an empty picker', async ({ page, mockRoute }) => {
		// "Nobody to send to" and "we could not find out" are different answers;
		// only one of them is actionable, and the honest one must not be the
		// one that disappears.
		let failedOnce = false;
		await mockRoute(page, '**/rest/v1/user_follows*', async (route) => {
			if (!failedOnce) {
				failedOnce = true;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated transient failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.getByTestId('route-send-dm-btn').click();

		const dialog = page.getByTestId('send-route-dialog');
		const loadError = dialog.getByTestId('send-route-load-error');
		await expect(loadError).toBeVisible({ timeout: 10_000 });
		await expect(dialog.getByText("You don't follow anyone yet", { exact: false })).toHaveCount(0);

		await loadError.getByRole('button', { name: 'Retry' }).click();
		await expect(dialog.getByRole('button', { name: /Alex Chen/ })).toBeVisible({
			timeout: 10_000
		});
	});

	test('a refused send says so instead of reporting success', async ({ page }) => {
		await page.route('**/rest/v1/direct_messages*', async (route) => {
			if (route.request().method() !== 'POST') {
				await route.continue();
				return;
			}
			await route.fulfill({
				status: 403,
				contentType: 'application/json',
				body: JSON.stringify({ code: '42501', message: 'permission denied' })
			});
		});

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.getByTestId('route-send-dm-btn').click();

		const dialog = page.getByTestId('send-route-dialog');
		await dialog.getByRole('button', { name: /Alex Chen/ }).click();

		await expect(dialog.getByTestId('send-route-error')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('send-route-sent')).toHaveCount(0);
	});
});
