import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /messages/[id] — a long conversation pages from its newest end.
 *
 * The thread read `created_at` ascending with a 200-row limit, so a
 * conversation past 200 messages never showed its newest ones. It now reads
 * the newest 50 on `(created_at, id)` and a "Load earlier messages" control
 * pages back from the oldest one shown (lib/social/dm_thread.ts, mirroring
 * mobile's `fetchDmThread`).
 *
 * Seeds 60 messages USER_B → USER_A, one minute apart, through the admin
 * client (service_role is exempt from the send rate limit). Sixty is past one
 * page and short of two, so the first read shows #11–#60 and one Load earlier
 * brings in #01–#10 and ends the thread. Teardown deletes the pair's messages
 * in both directions.
 */

const COUNT = 60;
const PAGE = 50;
const BASE_MS = Date.parse('2026-01-01T00:00:00.000Z');

const label = (tag: string, i: number) => `${tag} #${String(i).padStart(2, '0')}`;

async function clearPair() {
	await getAdminClient()
		.from('direct_messages')
		.delete()
		.in('sender_id', [USER_A.id, USER_B.id])
		.in('recipient_id', [USER_A.id, USER_B.id]);
}

test.describe('/messages — long thread paging', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(clearPair);
	test.afterEach(clearPair);

	test('opens on the newest page and Load earlier reveals the oldest', async ({ page }) => {
		const tag = `e2e page ${Date.now()}`;
		const rows = Array.from({ length: COUNT }, (_, k) => ({
			sender_id: USER_B.id,
			recipient_id: USER_A.id,
			body: label(tag, k + 1),
			created_at: new Date(BASE_MS + k * 60_000).toISOString()
		}));
		const { error } = await getAdminClient().from('direct_messages').insert(rows);
		expect(error).toBeNull();

		const firstRead = page.waitForRequest(
			(r) => r.method() === 'GET' && r.url().includes('/rest/v1/direct_messages')
		);
		await page.goto(`/messages/${USER_B.id}`);
		const url = decodeURIComponent((await firstRead).url());
		expect(url).toContain('order=created_at.desc');
		expect(url).toContain(`limit=${PAGE + 1}`);

		const thread = page.locator('.messages');
		const bubble = (i: number) => thread.getByText(label(tag, i), { exact: true });

		// The newest message is there, and the pane opens scrolled to it.
		await expect(bubble(COUNT)).toBeVisible({ timeout: 15_000 });
		await expect(bubble(COUNT)).toBeInViewport();
		await expect(bubble(COUNT - PAGE + 1)).toBeAttached();
		await expect(bubble(COUNT - PAGE)).toHaveCount(0);
		await expect(bubble(1)).toHaveCount(0);
		await expect(thread.locator('.bubble')).toHaveCount(PAGE);

		const loadEarlier = thread.getByRole('button', { name: 'Load earlier messages' });
		await expect(loadEarlier).toBeVisible();
		await loadEarlier.click();

		await expect(bubble(1)).toBeAttached({ timeout: 10_000 });
		await expect(thread.locator('.bubble')).toHaveCount(COUNT);
		// The page went in ABOVE what was on screen, which stays put.
		await expect(bubble(COUNT - PAGE + 1)).toBeInViewport();
		// Sixty is short of two pages, so the thread is exhausted.
		await expect(loadEarlier).toHaveCount(0);

		// Rendered oldest first across the page boundary.
		const texts = await thread.locator('.bubble .text').allTextContents();
		expect(texts).toEqual(Array.from({ length: COUNT }, (_, k) => label(tag, k + 1)));
	});

	test('a failed Load earlier says so and the control retries', async ({ page, mockRoute }) => {
		const tag = `e2e page fail ${Date.now()}`;
		const rows = Array.from({ length: PAGE + 1 }, (_, k) => ({
			sender_id: USER_B.id,
			recipient_id: USER_A.id,
			body: label(tag, k + 1),
			created_at: new Date(BASE_MS + k * 60_000).toISOString()
		}));
		const { error } = await getAdminClient().from('direct_messages').insert(rows);
		expect(error).toBeNull();

		await page.goto(`/messages/${USER_B.id}`);
		const thread = page.locator('.messages');
		await expect(thread.getByText(label(tag, PAGE + 1), { exact: true })).toBeVisible({ timeout: 15_000 });

		// Only the older-page read carries the keyset `or=`.
		let failing = true;
		await mockRoute(page, '**/rest/v1/direct_messages*', async (route) => {
			const older = route.request().method() === 'GET' && route.request().url().includes('or=');
			if (older && failing) {
				failing = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated transient failure' })
				});
			} else {
				await route.continue();
			}
		});

		const loadEarlier = thread.getByRole('button', { name: 'Load earlier messages' });
		await loadEarlier.click();
		await expect(thread.getByRole('alert')).toHaveText('Couldn’t load earlier messages.');
		await expect(thread.getByText(label(tag, 1), { exact: true })).toHaveCount(0);

		await loadEarlier.click();
		await expect(thread.getByText(label(tag, 1), { exact: true })).toBeAttached({ timeout: 10_000 });
		await expect(thread.getByRole('alert')).toHaveCount(0);
		await expect(loadEarlier).toHaveCount(0);
	});
});
