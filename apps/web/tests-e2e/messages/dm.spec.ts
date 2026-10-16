import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';
import { setStorageOnLoad } from '../fixtures/helpers';

/**
 * /messages — direct messages (very-social persona #55).
 *
 * USER_A (runner) and USER_B follow each other in the seed, so the
 * follow-graph send gate is satisfied. Sends a DM and asserts it lands
 * in the conversation + the thread list. afterEach clears the test
 * messages so the seed shape is intact.
 */

test.describe('/messages — direct messages', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		await getAdminClient()
			.from('direct_messages')
			.delete()
			.eq('sender_id', USER_A.id)
			.eq('recipient_id', USER_B.id);
	});

	test('sends a DM to a followed runner and it appears in the thread', async ({ page }) => {
		const body = `e2e hello ${Date.now()}`;
		await page.goto(`/messages/${USER_B.id}`);

		const composer = page.getByPlaceholder('Message…');
		await expect(composer).toBeVisible({ timeout: 10_000 });
		await composer.fill(body);
		await page.getByRole('button', { name: 'Send' }).click();

		// The sent message renders as a bubble in the conversation. Match the
		// body EXACTLY: the thread-list preview also contains it as "You: <body>",
		// so a substring getByText resolves to two elements (strict-mode
		// violation) once that preview has rendered.
		await expect(page.getByText(body, { exact: true })).toBeVisible({ timeout: 10_000 });

		// And the conversation shows in the thread list with a "You:" preview.
		await expect(page.locator('.thread', { hasText: /You:/ }).first()).toBeVisible();
	});

	test('a failed thread-list load surfaces a retry instead of "no conversations"', async ({
		page,
		mockRoute
	}) => {
		// Pin the unswallowed-failure contract: a transient dm_threads RPC
		// failure must render the error + Retry state, NOT the empty-inbox
		// copy (which stranded users — and flaked CI, run 28838002281 —
		// when fetchDmThreads returned [] on error). First call 500s, the
		// retry goes through.
		let failedOnce = false;
		await mockRoute(page, '**/rest/v1/rpc/dm_threads*', async (route) => {
			if (!failedOnce) {
				failedOnce = true;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated transient failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto('/messages');
		const errorNote = page.locator('.threads [role="alert"]');
		await expect(errorNote).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('No conversations yet', { exact: false })).toHaveCount(0);

		await errorNote.getByRole('button', { name: 'Retry' }).click();
		// The retry hits the real RPC: either threads render or the honest
		// empty state does — the error note is gone either way.
		await expect(errorNote).toHaveCount(0, { timeout: 10_000 });
	});

	test('a failed thread load surfaces a retry instead of a stale/empty pane', async ({ page, mockRoute }) => {
		// Pin the openThread unswallowed-failure contract: a transient
		// direct_messages select failure must render the error + Retry
		// state, NOT leave the user on the previous conversation (or the
		// "no messages yet" copy) with no sign anything broke. First call
		// 500s, the retry goes through.
		let failedOnce = false;
		await mockRoute(page, '**/rest/v1/direct_messages*', async (route) => {
			if (route.request().method() === 'GET' && !failedOnce) {
				failedOnce = true;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated transient failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto(`/messages/${USER_B.id}`);
		const errorNote = page.locator('.messages [role="alert"]');
		await expect(errorNote).toBeVisible({ timeout: 10_000 });
		await expect(page.getByText('No messages yet', { exact: false })).toHaveCount(0);

		await errorNote.getByRole('button', { name: 'Retry' }).click();
		// The retry hits the real endpoint: either messages render or the
		// honest empty state does — the error note is gone either way.
		await expect(errorNote).toHaveCount(0, { timeout: 10_000 });
	});

	// Mark-read stops at the newest message the reader was shown, so a reply
	// that lands between the thread read and the mark-read stays unread
	// (decisions § 1916, the mobile rule).
	test('opening a thread marks read only up to the newest message shown', async ({ page }) => {
		const admin = getAdminClient();
		const { data: seeded, error } = await admin
			.from('direct_messages')
			.insert({ sender_id: USER_B.id, recipient_id: USER_A.id, body: `e2e bound ${Date.now()}` })
			.select('id, created_at')
			.single();
		expect(error).toBeNull();
		try {
			const patch = page.waitForRequest(
				(r) => r.method() === 'PATCH' && r.url().includes('/rest/v1/direct_messages')
			);
			await page.goto(`/messages/${USER_B.id}`);
			const url = decodeURIComponent((await patch).url());
			expect(url).toContain(`created_at.lt."${seeded!.created_at}"`);
			expect(url).toContain(`id.lte.${seeded!.id}`);
		} finally {
			await admin.from('direct_messages').delete().eq('sender_id', USER_B.id).eq('recipient_id', USER_A.id);
		}
	});

	// A failed route read is not cached, so the card recovers the next time the
	// bubble mounts — here, switching to another thread and back without a reload.
	test('a route card whose read failed loads on the next mount', async ({ page, mockRoute }) => {
		const admin = getAdminClient();
		await admin.from('routes').update({ is_public: true }).eq('id', RUNNER_PUBLIC_ROUTE_ID);
		await admin.from('direct_messages').insert([
			{
				sender_id: USER_B.id,
				recipient_id: USER_A.id,
				body: 'e2e route card retry',
				route_id: RUNNER_PUBLIC_ROUTE_ID
			},
			{ sender_id: USER_C_PRO.id, recipient_id: USER_A.id, body: `e2e other thread ${Date.now()}` }
		]);
		try {
			let failing = true;
			const fail = async (route: import('@playwright/test').Route) => {
				if (failing) {
					await route.fulfill({
						status: 500,
						contentType: 'application/json',
						body: JSON.stringify({ message: 'simulated transient failure' })
					});
				} else {
					await route.continue();
				}
			};
			// USER_A owns the seeded route, so the card reads the base table.
			await mockRoute(page, '**/rest/v1/routes*', fail);

			await page.goto(`/messages/${USER_B.id}`);
			await expect(page.getByTestId('dm-route-attachment-unavailable')).toBeVisible({ timeout: 15_000 });

			failing = false;
			await page.locator(`a.thread[href="/messages/${USER_C_PRO.id}"]`).click();
			await expect(page.getByText('e2e other thread', { exact: false }).first()).toBeVisible({ timeout: 10_000 });
			await page.locator(`a.thread[href="/messages/${USER_B.id}"]`).click();
			await expect(page.getByTestId('dm-route-attachment')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('dm-route-attachment-unavailable')).toHaveCount(0);
		} finally {
			await admin
				.from('direct_messages')
				.delete()
				.in('sender_id', [USER_B.id, USER_C_PRO.id])
				.eq('recipient_id', USER_A.id);
		}
	});

	test('anon is prompted to sign in', async ({ page, context }) => {
		await context.clearCookies();
		await setStorageOnLoad(page.context(), { clearLocal: true });
		await page.goto('/messages');
		// Either the in-page sign-in prompt or a redirect to login.
		await expect(
			page.getByText(/Sign in to see your messages|Sign in/i).first()
		).toBeVisible({ timeout: 10_000 });
	});
});
