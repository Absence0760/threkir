import { expect, test } from '../fixtures/test';

import { readMaybeRow, readRows } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Block and unblock from inside a conversation (issue #1216).
 *
 * The header's Block goes through the same `block_user` RPC the profile uses,
 * behind the same confirm; Unblock runs at once. While the viewer's block
 * stands the composer gives way to a notice, which is what the INSERT policy
 * already enforces (pgtap: direct_messages_test.sql pins both directions).
 *
 * block_user drains the follow edge both ways, so this runs on two ephemeral
 * saga users rather than the seeded pair every other DM spec relies on.
 */

test.describe('/messages — block from the conversation', () => {
	test.describe.configure({ timeout: 60_000 });

	let users: SagaUser[] = [];
	let viewer: SagaUser;
	let partner: SagaUser;

	test.beforeAll(async () => {
		const stamp = Date.now().toString(36);
		users = await createSagaUsers(2, {
			displayNames: [`Blocker ${stamp}`, `Partner ${stamp}`]
		});
		[viewer, partner] = users;
		const admin = getAdminClient();
		const { error: followError } = await admin.from('user_follows').insert([
			{ follower_id: viewer.id, followee_id: partner.id },
			{ follower_id: partner.id, followee_id: viewer.id }
		]);
		if (followError) throw new Error(`follow seed failed: ${followError.message}`);
		const { error: msgError } = await admin
			.from('direct_messages')
			.insert({ sender_id: partner.id, recipient_id: viewer.id, body: `hello ${stamp}` });
		if (msgError) throw new Error(`message seed failed: ${msgError.message}`);
	});

	test.afterAll(async () => {
		if (users.length > 0) await deleteSagaUsers(users);
	});

	test('Block confirms, swaps the composer for a notice, and Unblock brings it back', async ({
		browser
	}) => {
		const ctx = await browser.newContext({ storageState: viewer.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		const admin = getAdminClient();
		const blockRow = () =>
			readMaybeRow(
				'the viewer\'s block',
				admin
					.from('user_blocks')
					.select('blocker_id')
					.eq('blocker_id', viewer.id)
					.eq('blocked_id', partner.id)
					.maybeSingle()
			);
		try {
			await page.goto(`/messages/${partner.id}`);
			const composer = page.getByPlaceholder('Message…');
			await expect(composer).toBeVisible({ timeout: 10_000 });
			const toggle = page.getByTestId('dm-block-toggle');
			await expect(toggle).toHaveText('Block');
			await expect(toggle).toHaveAttribute('aria-pressed', 'false');

			// Cancelling the confirm records nothing.
			await toggle.click();
			const dialog = page.getByTestId('dm-block-confirm');
			await expect(dialog).toBeVisible();
			await expect(dialog).toContainText(`Block ${partner.displayName}?`);
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			await expect(composer).toBeVisible();
			expect(await blockRow()).toBeNull();

			await toggle.click();
			await dialog.getByRole('button', { name: 'Block', exact: true }).click();

			const notice = page.getByTestId('dm-blocked-notice');
			await expect(notice).toContainText(
				`You blocked ${partner.displayName}, so neither of you can message the other.`,
				{ timeout: 10_000 }
			);
			await expect(composer).toHaveCount(0);
			await expect(page.getByRole('button', { name: 'Send' })).toHaveCount(0);
			await expect(toggle).toHaveText('Unblock');
			await expect(toggle).toHaveAttribute('aria-pressed', 'true');

			expect(await blockRow()).not.toBeNull();
			const follows = await readRows(
				'the follow edges between the pair',
				admin
					.from('user_follows')
					.select('follower_id')
					.in('follower_id', [viewer.id, partner.id])
					.in('followee_id', [viewer.id, partner.id])
			);
			expect(follows).toHaveLength(0);

			// The block is read back from the server, not just held in the page.
			await page.reload();
			await expect(notice).toBeVisible({ timeout: 10_000 });
			await expect(composer).toHaveCount(0);

			// Unblock is not confirmed.
			await notice.getByRole('button', { name: 'Unblock' }).click();
			await expect(composer).toBeVisible({ timeout: 10_000 });
			await expect(dialog).toBeHidden();
			await expect(toggle).toHaveText('Block');
			await expect.poll(blockRow, { timeout: 10_000 }).toBeNull();
		} finally {
			await ctx.close();
		}
	});
});
