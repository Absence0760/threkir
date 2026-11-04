import { expect, test } from '../fixtures/test';

import { readMaybeRow, readRows } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Mute, archive and delete-for-me from the conversation header (issue #1216,
 * migration 20271105000010). Each writes the viewer's own
 * conversation_participants row and nothing of the partner's; pgtap
 * (dm_conversations_test.sql) pins the read-path and notification rules, and
 * this pins what the page does with them.
 *
 * A fresh pair per test, because every test changes the pair's conversation
 * state and the seeded pair is shared with the other DM specs.
 */

test.describe('/messages — mute, archive and delete a conversation', () => {
	test.describe.configure({ timeout: 60_000 });

	let users: SagaUser[] = [];

	test.afterEach(async () => {
		if (users.length > 0) await deleteSagaUsers(users);
		users = [];
	});

	async function pair(label: string) {
		const stamp = `${label} ${Date.now().toString(36)}`;
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
			.select('conversation_id')
			.single();
		if (error || !data) throw new Error(`message seed failed: ${error?.message}`);
		return { viewer, partner, stamp, conversationId: data.conversation_id as string };
	}

	function viewerState(viewer: SagaUser, conversationId: string) {
		return readMaybeRow(
			"the viewer's conversation state",
			getAdminClient()
				.from('conversation_participants')
				.select('muted_at, archived_at, hidden_before')
				.eq('conversation_id', conversationId)
				.eq('user_id', viewer.id)
				.maybeSingle()
		);
	}

	test('Mute marks the inbox row and Unmute clears it, on the viewer only', async ({ browser }) => {
		const { viewer, partner, conversationId } = await pair('mute');
		const ctx = await browser.newContext({ storageState: viewer.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		try {
			await page.goto(`/messages/${partner.id}`);
			const toggle = page.getByTestId('dm-mute-toggle');
			await expect(toggle).toHaveAttribute('aria-pressed', 'false', { timeout: 10_000 });
			await expect(toggle).toHaveAccessibleName('Mute');

			await toggle.click();
			await expect(toggle).toHaveAttribute('aria-pressed', 'true');
			await expect(toggle).toHaveAccessibleName('Unmute');
			await expect(page.getByTestId('inbox-muted-mark')).toHaveCount(1);
			await expect
				.poll(async () => (await viewerState(viewer, conversationId))?.muted_at ?? null, { timeout: 10_000 })
				.not.toBeNull();
			const partnerRow = await readMaybeRow(
				"the partner's conversation state",
				getAdminClient()
					.from('conversation_participants')
					.select('muted_at')
					.eq('conversation_id', conversationId)
					.eq('user_id', partner.id)
					.maybeSingle()
			);
			expect(partnerRow?.muted_at ?? null).toBeNull();

			await page.reload();
			await expect(page.getByTestId('inbox-muted-mark')).toHaveCount(1, { timeout: 10_000 });

			await page.getByTestId('dm-mute-toggle').click();
			await expect(page.getByTestId('inbox-muted-mark')).toHaveCount(0);
			await expect
				.poll(async () => (await viewerState(viewer, conversationId))?.muted_at ?? null, { timeout: 10_000 })
				.toBeNull();
		} finally {
			await ctx.close();
		}
	});

	test('a conversation the inbox list never loaded still flips its toggles', async ({ browser }) => {
		const { viewer, partner, conversationId } = await pair('unlisted');
		const ctx = await browser.newContext({ storageState: viewer.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		// The list read fails throughout, so the open conversation has no inbox
		// row and its state can only come from what the viewer wrote.
		await page.route('**/rest/v1/rpc/dm_threads**', (route) =>
			route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' })
		);
		try {
			await page.goto(`/messages/${partner.id}`);
			const mute = page.getByTestId('dm-mute-toggle');
			await expect(mute).toHaveAttribute('aria-pressed', 'false', { timeout: 10_000 });

			await mute.click();
			await expect(mute).toHaveAttribute('aria-pressed', 'true');
			await expect
				.poll(async () => (await viewerState(viewer, conversationId))?.muted_at ?? null, { timeout: 10_000 })
				.not.toBeNull();

			// A second tap unmutes rather than resending the mute.
			await mute.click();
			await expect(mute).toHaveAttribute('aria-pressed', 'false');
			await expect
				.poll(async () => (await viewerState(viewer, conversationId))?.muted_at ?? null, { timeout: 10_000 })
				.toBeNull();

			const archive = page.getByTestId('dm-archive-toggle');
			await archive.click();
			await expect(archive).toHaveAttribute('aria-pressed', 'true');
			await expect
				.poll(async () => (await viewerState(viewer, conversationId))?.archived_at ?? null, { timeout: 10_000 })
				.not.toBeNull();
		} finally {
			await ctx.close();
		}
	});

	test('Archive files the conversation away until a newer message arrives', async ({ browser }) => {
		const { viewer, partner, stamp } = await pair('archive');
		const ctx = await browser.newContext({ storageState: viewer.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		const partnerName = `Partner ${stamp}`;
		try {
			await page.goto(`/messages/${partner.id}`);
			const threads = page.locator('aside.threads');
			await expect(threads.getByText(partnerName)).toBeVisible({ timeout: 10_000 });

			await page.getByTestId('dm-archive-toggle').click();
			await expect(threads.getByText(partnerName)).toHaveCount(0);
			const showArchived = page.getByTestId('inbox-show-archived');
			await expect(showArchived).toHaveText(/Archived \(1\)/);

			await showArchived.click();
			await expect(threads.getByText(partnerName)).toBeVisible();
			await page.getByTestId('inbox-back-to-inbox').click();
			await expect(threads.getByText(partnerName)).toHaveCount(0);

			const { error } = await getAdminClient()
				.from('direct_messages')
				.insert({ sender_id: partner.id, recipient_id: viewer.id, body: `back again ${stamp}` });
			if (error) throw new Error(`reply seed failed: ${error.message}`);
			await page.reload();
			await expect(threads.getByText(partnerName)).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('inbox-show-archived')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});

	test('Delete takes the undo bar: Undo keeps it, letting it run deletes it for the viewer only', async ({
		browser
	}) => {
		const { viewer, partner, stamp, conversationId } = await pair('delete');
		const ctx = await browser.newContext({ storageState: viewer.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		const partnerName = `Partner ${stamp}`;
		try {
			await page.goto(`/messages/${partner.id}`);
			const threads = page.locator('aside.threads');
			await expect(threads.getByText(partnerName)).toBeVisible({ timeout: 10_000 });

			// No confirm dialog: the delete is held, so Undo cancels it outright.
			await page.getByTestId('dm-delete-conversation').click();
			await expect(page.getByRole('dialog')).toHaveCount(0);
			await expect(page.getByTestId('dm-conversation-deleted')).toBeVisible();
			await expect(threads.getByText(partnerName)).toHaveCount(0);
			await page.getByTestId('undo-action').click();
			await expect(threads.getByText(partnerName)).toBeVisible();
			await expect(page.getByTestId('dm-conversation-deleted')).toHaveCount(0);
			expect((await viewerState(viewer, conversationId))?.hidden_before ?? null).toBeNull();

			await page.getByTestId('dm-delete-conversation').click();
			await page.getByTestId('undo-dismiss').click();
			await expect
				.poll(async () => (await viewerState(viewer, conversationId))?.hidden_before ?? null, {
					timeout: 10_000
				})
				.not.toBeNull();

			await page.goto('/messages');
			await expect(page.getByText(partnerName)).toHaveCount(0, { timeout: 10_000 });

			const partnerCopy = await readRows(
				"the partner's messages",
				getAdminClient().from('direct_messages').select('id').eq('conversation_id', conversationId)
			);
			expect(partnerCopy).toHaveLength(1);
		} finally {
			await ctx.close();
		}
	});
});
