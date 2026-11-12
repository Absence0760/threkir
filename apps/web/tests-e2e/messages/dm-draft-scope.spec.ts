import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /messages/[[id]] — an unsent draft belongs to the thread it was typed in.
 *
 * The composer lives inside the `{#if !activeId}{:else}` branch, so switching
 * conversations never tears it down, and the draft was a single top-level
 * `$state` that no thread change reset. A half-written private message to one
 * person therefore followed the viewer into the next conversation they clicked
 * — with the Send button live, and `send()` posting to the CURRENT `activeId`.
 * Keying drafts by partner also restores the right draft on switching back
 * rather than destroying it.
 *
 * USER_A (the storage state) mutually follows both USER_B and USER_C_PRO in
 * the seed, so both are permitted conversations to type into. Nothing is sent:
 * the whole point is the UNSENT buffer.
 */

test.describe('/messages — drafts are per conversation', () => {
	test.use({ storageState: USER_A.storageStatePath });

	// The sidebar only lists conversations that EXIST, so both threads need at
	// least one message before they can be clicked between.
	const seeded: string[] = [];
	test.beforeAll(async () => {
		const admin = getAdminClient();
		for (const partner of [USER_B, USER_C_PRO]) {
			const { data, error } = await admin
				.from('direct_messages')
				.insert({
					sender_id: USER_A.id,
					recipient_id: partner.id,
					body: 'draft-scope fixture'
				})
				.select('id')
				.single();
			expect(error, 'direct_messages seed must insert').toBeNull();
			if (data?.id) seeded.push(data.id as string);
		}
	});

	test.afterAll(async () => {
		if (seeded.length === 0) return;
		await getAdminClient().from('direct_messages').delete().in('id', seeded);
	});

	test('a draft does not follow you into another conversation', async ({ page }) => {
		const secret = 'key is under the mat';

		// Start in one thread. The thread LIST is always visible beside the
		// composer, so switching is a client-side nav that never remounts the
		// page — which is exactly why a page-level draft leaked across it.
		await page.goto(`/messages/${USER_C_PRO.id}`);
		const composer = page.locator('.composer textarea');
		await expect(composer).toBeVisible({ timeout: 15_000 });
		await composer.fill(secret);
		await expect(composer).toHaveValue(secret);

		const otherThread = page.locator(`a.thread[href="/messages/${USER_B.id}"]`);
		await expect(otherThread).toBeVisible({ timeout: 15_000 });
		await otherThread.click();
		await expect(page).toHaveURL(new RegExp(`/messages/${USER_B.id}$`));

		// The other person's composer must be empty — not holding a private
		// message meant for someone else, one Enter away from being sent.
		await expect(composer).toHaveValue('');

		// ...and clicking back restores the draft rather than destroying it.
		const firstThread = page.locator(`a.thread[href="/messages/${USER_C_PRO.id}"]`);
		await firstThread.click();
		await expect(page).toHaveURL(new RegExp(`/messages/${USER_C_PRO.id}$`));
		await expect(composer).toHaveValue(secret);
	});

	test('text typed while a send is in flight stays in the composer', async ({ page }) => {
		const stamp = Date.now();
		const sent = `slow one ${stamp}`;
		const meanwhile = `typed meanwhile ${stamp}`;
		await page.goto(`/messages/${USER_B.id}`);
		const composer = page.locator('.composer textarea');
		await expect(composer).toBeVisible({ timeout: 15_000 });

		let release!: () => void;
		const held = new Promise<void>((r) => (release = r));
		await page.route('**/rest/v1/direct_messages*', async (route) => {
			if (route.request().method() === 'POST') await held;
			await route.continue();
		});
		try {
			await composer.fill(sent);
			await page.getByRole('button', { name: 'Send', exact: true }).click();
			await composer.fill(meanwhile);
			release();
			await expect(page.getByTestId('dm-bubble').filter({ hasText: sent })).toBeVisible({ timeout: 10_000 });
			// The send has settled once the button is live again with text in the
			// composer; by then its success handler has run.
			await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
			await expect(composer).toHaveValue(meanwhile);
		} finally {
			await getAdminClient()
				.from('direct_messages')
				.delete()
				.eq('sender_id', USER_A.id)
				.eq('body', sent);
		}
	});
});
