import { expect, test } from '../fixtures/test';

import { readRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Unsend + report inside a conversation, and a deleted partner's thread
 * (issue #1216, migration 20271021000003).
 *
 * USER_A and USER_B follow each other in the seed. Messages are seeded through
 * the service role so each test owns exactly the rows it asserts on, and every
 * row it created is removed afterwards (the service role keeps the DELETE that
 * clients no longer have).
 */

test.describe('/messages — unsend, report, deleted account', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const seeded: string[] = [];

	async function seed(row: {
		sender_id: string;
		recipient_id: string;
		body: string;
	}): Promise<string> {
		const { data, error } = await getAdminClient()
			.from('direct_messages')
			.insert(row)
			.select('id')
			.single();
		if (error || !data) throw new Error(`seed failed: ${error?.message}`);
		seeded.push(data.id as string);
		return data.id as string;
	}

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (seeded.length > 0) {
			await admin.from('reports').delete().eq('target_kind', 'direct_message').in('target_id', seeded);
			await admin.from('direct_messages').delete().in('id', seeded);
		}
		seeded.length = 0;
	});

	test('the sender unsends their own message after confirming, and it reads as unsent', async ({
		page
	}) => {
		const body = `e2e unsend ${Date.now()}`;
		const id = await seed({ sender_id: USER_A.id, recipient_id: USER_B.id, body });

		await page.goto(`/messages/${USER_B.id}`);
		const bubble = page.getByTestId('dm-bubble').filter({ hasText: body });
		await expect(bubble).toBeVisible({ timeout: 10_000 });
		// My own message offers Unsend, never Report.
		await expect(bubble.getByRole('button', { name: 'Report' })).toHaveCount(0);

		// Cancelling leaves the message as it was.
		await bubble.getByRole('button', { name: 'Unsend' }).click();
		const dialog = page.getByTestId('dm-unsend-confirm');
		await expect(dialog).toBeVisible();
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(bubble).toBeVisible();

		await bubble.getByRole('button', { name: 'Unsend' }).click();
		await dialog.getByRole('button', { name: 'Unsend' }).click();

		await expect(page.getByText(body, { exact: true })).toHaveCount(0, { timeout: 10_000 });
		await expect(
			page.getByTestId('dm-bubble').filter({ hasText: 'Message unsent' }).first()
		).toBeVisible();

		const row = await readRow(
			'the unsent message',
			getAdminClient().from('direct_messages').select('body, unsent_at').eq('id', id).single()
		);
		expect(row.body).toBeNull();
		expect(row.unsent_at).not.toBeNull();
	});

	test('the recipient reports the other person\'s message, and the report keeps a snapshot', async ({
		page
	}) => {
		await getAdminClient()
			.from('rate_limits')
			.delete()
			.eq('user_id', USER_A.id)
			.eq('bucket', 'create_report');
		const body = `e2e report ${Date.now()}`;
		const id = await seed({ sender_id: USER_B.id, recipient_id: USER_A.id, body });

		await page.goto(`/messages/${USER_B.id}`);
		const bubble = page.getByTestId('dm-bubble').filter({ hasText: body });
		await expect(bubble).toBeVisible({ timeout: 10_000 });
		// Their message offers Report, never Unsend.
		await expect(bubble.getByRole('button', { name: 'Unsend' })).toHaveCount(0);

		await bubble.getByRole('button', { name: 'Report' }).click();
		const dialog = page.getByRole('dialog', { name: 'Report this message' });
		await expect(dialog).toBeVisible();
		await dialog.getByRole('radio', { name: /Harassment/ }).check();
		await dialog.getByRole('button', { name: 'Submit report' }).click();
		await expect(page.getByText('Report submitted. Thanks for flagging.')).toBeVisible({
			timeout: 10_000
		});

		const report = await readRow(
			'the filed report',
			getAdminClient()
				.from('reports')
				.select('reason, snapshot_body, snapshot_author_id')
				.eq('target_kind', 'direct_message')
				.eq('target_id', id)
				.single()
		);
		expect(report.reason).toBe('harassment');
		expect(report.snapshot_body).toBe(body);
		expect(report.snapshot_author_id).toBe(USER_B.id);
	});

	test('a deleted partner\'s thread is listed as a deleted account and cannot be replied to', async ({
		page
	}) => {
		// Stand in for the partner's account deletion the way the FK action
		// does it: recipient_id goes to null, and the set-null trigger stamps
		// the conversation key.
		const body = `e2e to a deleted account ${Date.now()}`;
		const startedAt = new Date().toISOString();
		const id = await seed({ sender_id: USER_A.id, recipient_id: USER_B.id, body });
		const admin = getAdminClient();
		await admin
			.from('notifications')
			.delete()
			.eq('user_id', USER_B.id)
			.eq('actor_id', USER_A.id)
			.eq('kind', 'message')
			.gte('created_at', startedAt);
		const { error: nullError } = await admin
			.from('direct_messages')
			.update({ recipient_id: null })
			.eq('id', id);
		if (nullError) throw new Error(`deleting the partner failed: ${nullError.message}`);
		const { deleted_partner_key: key } = await readRow(
			'the stamped conversation key',
			admin.from('direct_messages').select('deleted_partner_key').eq('id', id).single()
		);

		await page.goto('/messages');
		const row = page.locator('.thread', { hasText: body });
		await expect(row).toBeVisible({ timeout: 10_000 });
		await expect(row).toContainText('Deleted account');

		await row.click();
		await expect(page).toHaveURL(new RegExp(`/messages/deleted-${key}$`));
		await expect(page.getByText(body, { exact: true })).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.conv-head .who')).toHaveText('Deleted account');
		await expect(page.getByPlaceholder('Message…')).toHaveCount(0);
		await expect(page.getByText("This account was deleted. You can still read the messages you sent, but you can't reply.")).toBeVisible();
	});
});
