import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Searching messages (issue #1216, migration 20271213121603). The search
 * box finds the viewer's own messages and opens the conversation; a word
 * that appears only in someone else's conversation finds nothing. pgtap
 * (dm_search_test.sql) pins that the RPC runs under the caller's RLS.
 */

async function openAs(browser: Browser, user: SagaUser): Promise<{ page: Page; close: () => Promise<void> }> {
	const ctx = await browser.newContext({ storageState: user.storageStatePath });
	await acceptCookieConsent(ctx);
	const page = await ctx.newPage();
	return { page, close: () => ctx.close() };
}

test.describe('/messages — search', () => {
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[] = [];

	test.afterEach(async () => {
		if (users.length > 0) await deleteSagaUsers(users);
		users = [];
	});

	test('finds the viewer own messages and nothing from other conversations', async ({ browser }) => {
		const stamp = Date.now().toString(36);
		users = await createSagaUsers(4, {
			displayNames: [`Seeker ${stamp}`, `Friend ${stamp}`, `Other ${stamp}`, `Another ${stamp}`]
		});
		const [seeker, friend, other, another] = users;
		const admin = getAdminClient();
		const { error: followError } = await admin.from('user_follows').insert([
			{ follower_id: seeker.id, followee_id: friend.id },
			{ follower_id: other.id, followee_id: another.id }
		]);
		if (followError) throw new Error(`follow seed failed: ${followError.message}`);
		const { error } = await admin.from('direct_messages').insert([
			{ sender_id: friend.id, recipient_id: seeker.id, body: `tempo zq${stamp} at seven` },
			{ sender_id: other.id, recipient_id: another.id, body: `secret xk${stamp} plan` }
		]);
		if (error) throw new Error(`message seed failed: ${error.message}`);

		const s = await openAs(browser, seeker);
		try {
			await s.page.goto('/messages');
			const box = s.page.getByTestId('inbox-search');
			await expect(box).toBeVisible({ timeout: 10_000 });

			await box.fill(`xk${stamp}`);
			await expect(s.page.getByTestId('inbox-search-empty')).toBeVisible({ timeout: 10_000 });

			await box.fill(`zq${stamp}`);
			const hit = s.page.getByTestId('inbox-search-hit');
			await expect(hit).toHaveCount(1, { timeout: 10_000 });
			await expect(hit).toContainText(`Friend ${stamp}`);
			await expect(hit.locator('mark')).toHaveText(`zq${stamp}`);
			await hit.click();
			await expect(s.page).toHaveURL(new RegExp(`/messages/${friend.id}$`));
			await expect(s.page.getByTestId('dm-bubble').filter({ hasText: `tempo zq${stamp}` })).toBeVisible();
		} finally {
			await s.close();
		}
	});
});
