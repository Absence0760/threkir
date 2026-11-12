import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { readRow } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Read receipts (issue #1216, migration 20271113000001). The sender sees
 * "Seen" under their newest message the partner has read, only while both
 * have receipts on; turning them off on Settings → Privacy hides receipts both
 * ways, including ones already shown. pgtap (dm_read_receipts_test.sql) pins
 * that the server withholds read_at; this pins what the page does with
 * seen_at.
 */

async function openAs(browser: Browser, user: SagaUser): Promise<{ page: Page; close: () => Promise<void> }> {
	const ctx = await browser.newContext({ storageState: user.storageStatePath });
	await acceptCookieConsent(ctx);
	const page = await ctx.newPage();
	return { page, close: () => ctx.close() };
}

async function setReceipts(page: Page, on: boolean) {
	await page.goto('/settings/privacy');
	const toggle = page.getByTestId('read-receipts-toggle');
	await expect(toggle).toBeChecked({ checked: !on, timeout: 10_000 });
	await toggle.click();
	await expect(toggle).toBeChecked({ checked: on });
}

test.describe('/messages — read receipts', () => {
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[] = [];

	test.afterEach(async () => {
		if (users.length > 0) await deleteSagaUsers(users);
		users = [];
	});

	async function seed(stamp: string) {
		users = await createSagaUsers(2, { displayNames: [`Sender ${stamp}`, `Reader ${stamp}`] });
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
				{ sender_id: sender.id, recipient_id: reader.id, body: `first ${stamp}`, created_at: new Date(Date.now() - 60_000).toISOString() },
				{ sender_id: sender.id, recipient_id: reader.id, body: `second ${stamp}`, created_at: new Date().toISOString() }
			])
			.select('id, body');
		if (error || !data) throw new Error(`message seed failed: ${error?.message}`);
		const second = data.find((r) => r.body === `second ${stamp}`)!;
		return { sender, reader, secondId: second.id as string };
	}

	const readState = (id: string) =>
		readRow('the sent message', getAdminClient().from('direct_messages').select('read_at, seen_at').eq('id', id).single());

	test('the sender sees Seen under their newest read message, and an opt-out withdraws it', async ({ browser }) => {
		const stamp = `seen ${Date.now().toString(36)}`;
		const { sender, reader, secondId } = await seed(stamp);

		const r = await openAs(browser, reader);
		try {
			await r.page.goto(`/messages/${sender.id}`);
			await expect(r.page.getByTestId('dm-bubble').getByText(`second ${stamp}`)).toBeVisible({ timeout: 10_000 });
			await expect.poll(async () => (await readState(secondId)).seen_at, { timeout: 10_000 }).not.toBeNull();
			// The reader sees no receipt on messages they received.
			await expect(r.page.getByTestId('dm-seen')).toHaveCount(0);
		} finally {
			await r.close();
		}

		const s = await openAs(browser, sender);
		try {
			await s.page.goto(`/messages/${reader.id}`);
			const seen = s.page.getByTestId('dm-seen');
			await expect(seen).toHaveCount(1, { timeout: 10_000 });
			await expect(seen).toContainText('Seen');
			// It sits under the newest message, not under each one.
			await expect(s.page.locator('[data-testid="dm-bubble"] + [data-testid="dm-seen"]')).toHaveCount(1);
			await expect(
				s.page.getByTestId('dm-bubble').filter({ hasText: `second ${stamp}` }).locator('+ [data-testid="dm-seen"]')
			).toHaveCount(1);

			// The sender opting out stops seeing receipts, the one already shown included.
			await setReceipts(s.page, false);
			await expect.poll(async () => (await readState(secondId)).seen_at, { timeout: 10_000 }).toBeNull();
			await s.page.goto(`/messages/${reader.id}`);
			await expect(s.page.getByTestId('dm-bubble').getByText(`second ${stamp}`)).toBeVisible({ timeout: 10_000 });
			await expect(s.page.getByTestId('dm-seen')).toHaveCount(0);
		} finally {
			await s.close();
		}
	});

	test('a reader who turned receipts off is never shown as having read', async ({ browser }) => {
		const stamp = `off ${Date.now().toString(36)}`;
		const { sender, reader, secondId } = await seed(stamp);

		const r = await openAs(browser, reader);
		try {
			await setReceipts(r.page, false);
			await r.page.goto(`/messages/${sender.id}`);
			await expect(r.page.getByTestId('dm-bubble').getByText(`second ${stamp}`)).toBeVisible({ timeout: 10_000 });
			// The reader's own read is still stored, so their unread count clears.
			await expect.poll(async () => (await readState(secondId)).read_at, { timeout: 10_000 }).not.toBeNull();
			expect((await readState(secondId)).seen_at).toBeNull();
		} finally {
			await r.close();
		}

		const s = await openAs(browser, sender);
		try {
			await s.page.goto(`/messages/${reader.id}`);
			await expect(s.page.getByTestId('dm-bubble').getByText(`second ${stamp}`)).toBeVisible({ timeout: 10_000 });
			await expect(s.page.getByTestId('dm-seen')).toHaveCount(0);
		} finally {
			await s.close();
		}
	});
});
