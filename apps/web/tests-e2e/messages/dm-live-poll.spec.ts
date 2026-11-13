import type { Request } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * The open conversation re-reads every 10 s and the inbox every 30 s while the
 * tab is visible, the cadences mobile polls at (decisions § 1916,
 * `DM_THREAD_POLL_MS` / `DM_INBOX_POLL_MS` in `social/dm_thread.ts`). The
 * page's clock is installed before it loads and fast-forwarded, so the spec
 * waits on no real interval. Messages are planted through the service role
 * after the page has drawn, so only a poll can bring them in.
 */

test.describe('/messages — live updates by polling', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const seeded: string[] = [];

	async function seed(row: { sender_id: string; recipient_id: string; body: string }) {
		const { data, error } = await getAdminClient()
			.from('direct_messages')
			.insert(row)
			.select('id')
			.single();
		if (error || !data) throw new Error(`seed failed: ${error?.message}`);
		seeded.push(data.id as string);
	}

	test.afterEach(async () => {
		if (seeded.length > 0) {
			await getAdminClient().from('direct_messages').delete().in('id', seeded);
		}
		seeded.length = 0;
	});

	test('a reply lands in the open conversation on the next poll, once', async ({ page }) => {
		await page.clock.install();
		await page.goto(`/messages/${USER_B.id}`);
		await expect(page.getByPlaceholder('Message…')).toBeVisible({ timeout: 10_000 });

		const body = `e2e poll reply ${Date.now()}`;
		await seed({ sender_id: USER_B.id, recipient_id: USER_A.id, body });
		const bubble = page.getByTestId('dm-bubble').filter({ hasText: body });
		await expect(bubble).toHaveCount(0);

		await page.clock.fastForward(10_000);
		await expect(bubble).toHaveCount(1, { timeout: 10_000 });

		// A second poll re-reads the same page and must not draw it twice.
		await page.clock.fastForward(10_000);
		await expect(bubble).toHaveCount(1);
	});

	test('a poll already in flight when you unsend does not bring the text back', async ({
		page
	}) => {
		const body = `e2e poll unsend ${Date.now()}`;
		await seed({ sender_id: USER_A.id, recipient_id: USER_B.id, body });
		await page.clock.install();
		await page.goto(`/messages/${USER_B.id}`);
		const bubble = page.getByTestId('dm-bubble').filter({ hasText: body });
		await expect(bubble).toBeVisible({ timeout: 10_000 });

		// Hold the next thread read with the pre-unsend answer already fetched,
		// so it lands after the unsend with the old text in it.
		let release!: () => void;
		const released = new Promise<void>((r) => (release = r));
		let intercepted!: () => void;
		const held = new Promise<void>((r) => (intercepted = r));
		let armed = true;
		await page.route('**/rest/v1/direct_messages?**', async (route) => {
			if (!armed || route.request().method() !== 'GET') return route.continue();
			armed = false;
			const stale = await route.fetch();
			intercepted();
			await released;
			await route.fulfill({ response: stale });
		});
		await page.clock.fastForward(10_000);
		await held;

		await bubble.getByRole('button', { name: 'Unsend' }).click();
		await page.getByTestId('dm-unsend-confirm').getByRole('button', { name: 'Unsend' }).click();
		const placeholder = page.getByTestId('dm-bubble').filter({ hasText: 'Message unsent' });
		await expect(placeholder.first()).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText(body, { exact: true })).toHaveCount(0);

		const staleAnswered = page.waitForResponse(
			(r) => r.url().includes('/rest/v1/direct_messages?') && r.request().method() === 'GET'
		);
		release();
		await staleAnswered;
		// Let the page finish handling the answer before reading the DOM.
		for (let i = 0; i < 5; i++) await page.evaluate(() => Promise.resolve());
		await expect(page.getByText(body, { exact: true })).toHaveCount(0);
		await expect(placeholder.first()).toBeVisible();
	});

	test('the inbox picks up a new conversation preview on its poll', async ({ page }) => {
		// The heading draws before the inbox's opening reads land: the list
		// read, and a second one once group_messages_enabled() answers true
		// (messages_inbox.svelte.ts loadGroups). A message planted while either
		// is in flight arrives without any poll, so plant only once a list read
		// issued after the flag answered has finished and none is in flight.
		// The sidebar's unread badge reads dm_threads() too, so reads are
		// counted rather than identified.
		let threadReads = 0;
		let threadReadsDone = 0;
		let readsAtFlag = -1;
		const isThreadRead = (url: string) => url.includes('/rest/v1/rpc/dm_threads');
		page.on('request', (r) => {
			if (isThreadRead(r.url())) threadReads++;
		});
		const settle = (r: Request) => {
			if (isThreadRead(r.url())) threadReadsDone++;
		};
		page.on('requestfinished', settle);
		page.on('requestfailed', settle);
		page.on('response', (r) => {
			if (r.url().includes('/rest/v1/rpc/group_messages_enabled')) readsAtFlag = threadReads;
		});
		const flagRead = page.waitForResponse((r) =>
			r.url().includes('/rest/v1/rpc/group_messages_enabled')
		);

		await page.clock.install();
		await page.goto('/messages');
		await expect(page.getByRole('heading', { name: 'Messages', level: 2 })).toBeVisible({
			timeout: 10_000
		});
		const groupsOn = (await (await flagRead).json()) === true;
		await expect
			.poll(
				() =>
					threadReadsDone === threadReads &&
					threadReadsDone > 0 &&
					(!groupsOn || threadReads > readsAtFlag),
				{ timeout: 10_000 }
			)
			.toBe(true);

		const body = `e2e inbox poll ${Date.now()}`;
		await seed({ sender_id: USER_C_PRO.id, recipient_id: USER_A.id, body });
		const row = page.locator('.thread', { hasText: body });

		// The thread poll's cadence is not the inbox's.
		await page.clock.fastForward(10_000);
		await expect(row).toHaveCount(0);

		await page.clock.fastForward(20_000);
		await expect(row).toBeVisible({ timeout: 10_000 });
	});
});
