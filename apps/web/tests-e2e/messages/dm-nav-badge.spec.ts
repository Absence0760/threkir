import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * The sidebar's Messages entry: the only way into /messages from the shell,
 * and its unread badge (decisions § 2007). USER_B and USER_C_PRO message
 * USER_A (both follow runner in the seed); afterEach removes every row this
 * spec wrote, matched on its body tag, so the seed shape is intact.
 */

const TAG = 'e2e nav badge';

test.describe('sidebar Messages entry', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		await getAdminClient().from('direct_messages').delete().like('body', `${TAG}%`);
	});

	test('counts unread messages across threads, and drops by one thread when it is read in place', async ({
		page,
	}) => {
		const stamp = Date.now();
		// 2 unread from B + 1 unread from C = 3. A's own message to B must not
		// count, and the total is messages, not threads (which would read 2).
		const { error } = await getAdminClient()
			.from('direct_messages')
			.insert([
				{ sender_id: USER_B.id, recipient_id: USER_A.id, body: `${TAG} b1 ${stamp}` },
				{ sender_id: USER_B.id, recipient_id: USER_A.id, body: `${TAG} b2 ${stamp}` },
				{ sender_id: USER_C_PRO.id, recipient_id: USER_A.id, body: `${TAG} c1 ${stamp}` },
				{ sender_id: USER_A.id, recipient_id: USER_B.id, body: `${TAG} a1 ${stamp}` },
			]);
		expect(error).toBeNull();

		await page.goto('/dashboard');
		const link = page.locator('a.nav-link[href="/messages"]');
		await expect(link).toBeVisible({ timeout: 10_000 });
		await expect(link).toContainText('Messages');
		await expect(link.locator('.nav-badge')).toHaveText('3', { timeout: 10_000 });
		await expect(link).toContainText('3 unread');

		await link.click();
		await expect(page).toHaveURL(/\/messages/);
		await expect(link).toHaveClass(/active/);

		// Opened by a client-side click, not page.goto: the layout's auth-ready
		// read does not run again, so only the /messages page's own refresh
		// after marking the thread read can move the badge. C's message is
		// still unread, so the badge drops to 1 rather than clearing.
		await page.locator(`a.thread[href="/messages/${USER_B.id}"]`).click();
		await expect(page).toHaveURL(new RegExp(`/messages/${USER_B.id}`));
		await expect(link.locator('.nav-badge')).toHaveText('1', { timeout: 10_000 });
		await expect(link).toContainText('1 unread');
	});
});
