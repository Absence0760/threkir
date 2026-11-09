import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { readRow } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Editing a sent message (issue #1216, migration 20271114000210). The sender
 * may rewrite their own message for 15 minutes; both sides then see the new
 * text and "Edited". Edit is not offered on an older message, nor on the
 * partner's, and a save the server refuses says so. pgtap (dm_edit_test.sql)
 * pins the server rules; this pins the page.
 */

async function openAs(browser: Browser, user: SagaUser): Promise<{ page: Page; close: () => Promise<void> }> {
	const ctx = await browser.newContext({ storageState: user.storageStatePath });
	await acceptCookieConsent(ctx);
	const page = await ctx.newPage();
	return { page, close: () => ctx.close() };
}

test.describe('/messages — edit a sent message', () => {
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[] = [];

	test.afterEach(async () => {
		if (users.length > 0) await deleteSagaUsers(users);
		users = [];
	});

	async function seed(stamp: string) {
		users = await createSagaUsers(2, { displayNames: [`Editor ${stamp}`, `Reader ${stamp}`] });
		const [sender, reader] = users;
		const admin = getAdminClient();
		const { error: followError } = await admin.from('user_follows').insert([
			{ follower_id: sender.id, followee_id: reader.id },
			{ follower_id: reader.id, followee_id: sender.id }
		]);
		if (followError) throw new Error(`follow seed failed: ${followError.message}`);
		const { data, error } = await admin
			.from('direct_messages')
			.insert([
				{ sender_id: sender.id, recipient_id: reader.id, body: `old ${stamp}`, created_at: new Date(Date.now() - 30 * 60_000).toISOString() },
				{ sender_id: reader.id, recipient_id: sender.id, body: `reply ${stamp}`, created_at: new Date(Date.now() - 2 * 60_000).toISOString() },
				{ sender_id: sender.id, recipient_id: reader.id, body: `fresh ${stamp}`, created_at: new Date(Date.now() - 60_000).toISOString() }
			])
			.select('id, body');
		if (error || !data) throw new Error(`message seed failed: ${error?.message}`);
		const fresh = data.find((r) => r.body === `fresh ${stamp}`)!;
		return { sender, reader, freshId: fresh.id as string };
	}

	const readMessage = (id: string) =>
		readRow('the edited message', getAdminClient().from('direct_messages').select('body, edited_at, original_body').eq('id', id).single());

	test('the sender edits a fresh message inline, and both sides see it marked edited', async ({ browser }) => {
		const stamp = `edit ${Date.now().toString(36)}`;
		const { sender, reader, freshId } = await seed(stamp);

		const s = await openAs(browser, sender);
		try {
			await s.page.goto(`/messages/${reader.id}`);
			const fresh = s.page.getByTestId('dm-bubble').filter({ hasText: `fresh ${stamp}` });
			await expect(fresh).toBeVisible({ timeout: 10_000 });
			// Only the sender's own message inside the window offers Edit.
			await expect(s.page.getByTestId('dm-bubble').filter({ hasText: `old ${stamp}` }).getByTestId('dm-edit')).toHaveCount(0);
			await expect(s.page.getByTestId('dm-bubble').filter({ hasText: `reply ${stamp}` }).getByTestId('dm-edit')).toHaveCount(0);

			await fresh.getByTestId('dm-edit').click();
			const input = s.page.getByTestId('dm-edit-input');
			await expect(input).toHaveValue(`fresh ${stamp}`);
			await input.fill(`fixed ${stamp}`);
			await s.page.getByTestId('dm-edit-save').click();

			const fixed = s.page.getByTestId('dm-bubble').filter({ hasText: `fixed ${stamp}` });
			await expect(fixed).toBeVisible();
			await expect(fixed.getByTestId('dm-edited')).toBeVisible();
			await expect(s.page.getByTestId('dm-edit-form')).toHaveCount(0);

			const row = await readMessage(freshId);
			expect(row.body).toBe(`fixed ${stamp}`);
			expect(row.edited_at).not.toBeNull();
			expect(row.original_body).toBe(`fresh ${stamp}`);
		} finally {
			await s.close();
		}

		const r = await openAs(browser, reader);
		try {
			await r.page.goto(`/messages/${sender.id}`);
			const fixed = r.page.getByTestId('dm-bubble').filter({ hasText: `fixed ${stamp}` });
			await expect(fixed).toBeVisible({ timeout: 10_000 });
			await expect(fixed.getByTestId('dm-edited')).toBeVisible();
			await expect(r.page.getByText(`fresh ${stamp}`)).toHaveCount(0);
			// The recipient cannot edit the sender's message, though their own
			// fresh reply offers Edit to them.
			await expect(fixed.getByTestId('dm-edit')).toHaveCount(0);
			await expect(r.page.getByTestId('dm-bubble').filter({ hasText: `reply ${stamp}` }).getByTestId('dm-edit')).toHaveCount(1);
		} finally {
			await r.close();
		}
	});

	test('Escape cancels an edit and leaves the message as it was', async ({ browser }) => {
		const stamp = `cancel ${Date.now().toString(36)}`;
		const { sender, reader, freshId } = await seed(stamp);

		const s = await openAs(browser, sender);
		try {
			await s.page.goto(`/messages/${reader.id}`);
			const fresh = s.page.getByTestId('dm-bubble').filter({ hasText: `fresh ${stamp}` });
			await expect(fresh).toBeVisible({ timeout: 10_000 });
			await fresh.getByTestId('dm-edit').click();
			await s.page.getByTestId('dm-edit-input').fill('never saved');
			await s.page.getByTestId('dm-edit-input').press('Escape');
			await expect(s.page.getByTestId('dm-edit-form')).toHaveCount(0);
			await expect(fresh.getByTestId('dm-edited')).toHaveCount(0);
			expect((await readMessage(freshId)).edited_at).toBeNull();
		} finally {
			await s.close();
		}
	});

	test('a save the server refuses keeps the editor open and says why', async ({ browser }) => {
		const stamp = `late ${Date.now().toString(36)}`;
		const { sender, reader, freshId } = await seed(stamp);

		const s = await openAs(browser, sender);
		try {
			await s.page.goto(`/messages/${reader.id}`);
			const fresh = s.page.getByTestId('dm-bubble').filter({ hasText: `fresh ${stamp}` });
			await expect(fresh).toBeVisible({ timeout: 10_000 });
			await fresh.getByTestId('dm-edit').click();

			// The window closes while the editor is open: the server's clock decides.
			const { error } = await getAdminClient()
				.from('direct_messages')
				.update({ created_at: new Date(Date.now() - 20 * 60_000).toISOString() })
				.eq('id', freshId);
			if (error) throw new Error(`backdate failed: ${error.message}`);

			await s.page.getByTestId('dm-edit-input').fill(`too late ${stamp}`);
			await s.page.getByTestId('dm-edit-save').click();
			await expect(s.page.getByTestId('dm-edit-error')).toHaveText('This message can no longer be edited.');
			await expect(s.page.getByTestId('dm-edit-form')).toBeVisible();
			expect((await readMessage(freshId)).body).toBe(`fresh ${stamp}`);
		} finally {
			await s.close();
		}
	});
});
