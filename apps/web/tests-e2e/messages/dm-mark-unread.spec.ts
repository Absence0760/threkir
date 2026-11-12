import { expect, test } from '../fixtures/test';

import { readMaybeRow, readRow } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Mark as unread from the conversation header (issue #1216 P2, migration
 * 20271109000020). The mark is the viewer's own conversation_participants
 * stamp: it leaves the conversation, the inbox row and the nav badge count it
 * as one, opening the conversation again clears it, and the partner's
 * read_at is never touched. pgtap (dm_mark_unread_test.sql) pins the count
 * and the RLS; this pins what the page does with them.
 */

test.describe('/messages — mark a conversation unread', () => {
	test.describe.configure({ timeout: 60_000 });

	let users: SagaUser[] = [];

	test.afterEach(async () => {
		if (users.length > 0) await deleteSagaUsers(users);
		users = [];
	});

	test('Mark as unread leaves, badges the row and the nav, and reopening clears it', async ({ browser }) => {
		const stamp = `unread ${Date.now().toString(36)}`;
		users = await createSagaUsers(2, { displayNames: [`Viewer ${stamp}`, `Partner ${stamp}`] });
		const [viewer, partner] = users;
		const admin = getAdminClient();
		const { error: followError } = await admin.from('user_follows').insert([
			{ follower_id: viewer.id, followee_id: partner.id },
			{ follower_id: partner.id, followee_id: viewer.id }
		]);
		if (followError) throw new Error(`follow seed failed: ${followError.message}`);
		const { data, error } = await admin
			.from('direct_messages')
			.insert({ sender_id: partner.id, recipient_id: viewer.id, body: `hello ${stamp}` })
			.select('id, conversation_id')
			.single();
		if (error || !data) throw new Error(`message seed failed: ${error?.message}`);
		const conversationId = data.conversation_id as string;

		const mark = () =>
			readMaybeRow(
				"the viewer's unread mark",
				getAdminClient()
					.from('conversation_participants')
					.select('marked_unread_at')
					.eq('conversation_id', conversationId)
					.eq('user_id', viewer.id)
					.maybeSingle()
			);

		const ctx = await browser.newContext({ storageState: viewer.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		try {
			await page.goto(`/messages/${partner.id}`);
			await expect(page.getByTestId('dm-bubble').getByText(`hello ${stamp}`)).toBeVisible({ timeout: 10_000 });
			const row = page.locator(`a.thread[href="/messages/${partner.id}"]`);
			// Opening the conversation read the partner's message.
			await expect(row.getByTestId('inbox-unread-count')).toHaveCount(0, { timeout: 10_000 });
			const navBadge = page.locator('a.nav-link[href="/messages"] .nav-badge');

			const button = page.getByTestId('dm-mark-unread');
			await expect(button).toHaveAccessibleName('Mark as unread');
			await button.click();

			await expect(page).toHaveURL(/\/messages\/?$/);
			await expect(row.getByTestId('inbox-unread-count')).toHaveText('1');
			await expect(navBadge).toHaveText('1', { timeout: 10_000 });
			await expect
				.poll(async () => (await mark())?.marked_unread_at ?? null, { timeout: 10_000 })
				.not.toBeNull();

			// The partner's message stays read: the mark is the viewer's alone.
			const sent = await readRow(
				"the partner's message",
				getAdminClient().from('direct_messages').select('read_at').eq('id', data.id as string).single()
			);
			expect(sent.read_at).not.toBeNull();

			await page.reload();
			await expect(row.getByTestId('inbox-unread-count')).toHaveText('1', { timeout: 10_000 });

			await row.click();
			await expect(page.getByTestId('dm-bubble').getByText(`hello ${stamp}`)).toBeVisible({ timeout: 10_000 });
			await expect
				.poll(async () => (await mark())?.marked_unread_at ?? null, { timeout: 10_000 })
				.toBeNull();
			await expect(row.getByTestId('inbox-unread-count')).toHaveCount(0);
			await expect(navBadge).toHaveCount(0, { timeout: 10_000 });
		} finally {
			await ctx.close();
		}
	});
});
