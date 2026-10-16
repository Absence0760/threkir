import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * The sidebar's Messages entry: the only way into /messages from the shell,
 * and its unread badge drops when a conversation is opened (decisions § 2007).
 * USER_B messages USER_A (they follow each other in the seed); afterEach
 * clears those rows so the seed shape is intact.
 */

test.describe('sidebar Messages entry', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		await getAdminClient()
			.from('direct_messages')
			.delete()
			.eq('sender_id', USER_B.id)
			.eq('recipient_id', USER_A.id);
	});

	test('shows the unread count, opens the inbox, and clears on read', async ({ page }) => {
		const { error } = await getAdminClient()
			.from('direct_messages')
			.insert([
				{ sender_id: USER_B.id, recipient_id: USER_A.id, body: `e2e nav badge 1 ${Date.now()}` },
				{ sender_id: USER_B.id, recipient_id: USER_A.id, body: `e2e nav badge 2 ${Date.now()}` },
			]);
		expect(error).toBeNull();

		await page.goto('/dashboard');
		const link = page.locator('a.nav-link[href="/messages"]');
		await expect(link).toBeVisible({ timeout: 10_000 });
		await expect(link).toContainText('Messages');
		await expect(link.locator('.nav-badge')).toHaveText('2', { timeout: 10_000 });
		await expect(link).toContainText('2 unread');

		await link.click();
		await expect(page).toHaveURL(/\/messages/);
		await expect(link).toHaveClass(/active/);

		await page.goto(`/messages/${USER_B.id}`);
		await expect(link.locator('.nav-badge')).toHaveCount(0, { timeout: 10_000 });
	});
});
