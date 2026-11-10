import { deflateSync } from 'node:zlib';

import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { readMaybeRow } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Photos and links in a message (issue #1216, migration 20271213121604).
 *
 * A link draws as its text plus a chip naming its domain, with no fetch, and
 * the anchor carries rel="noopener noreferrer nofollow ugc". A photo is
 * re-encoded in the browser, uploaded under the sender's own path and sent;
 * it shows as "Preparing" until the server's re-encoded copy is ready, then
 * as an image from a signed URL. The worker's re-encode is stood in for here
 * by the admin client; the Go tests pin the re-encode itself. The Settings
 * switch for message requests persists to user_settings.dm_requests.
 */

function crc32(buf: Buffer): number {
	let c = ~0;
	for (const b of buf) {
		c ^= b;
		for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
	}
	return ~c >>> 0;
}

function chunk(type: string, data: Buffer): Buffer {
	const len = Buffer.alloc(4);
	len.writeUInt32BE(data.length);
	const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
	const crc = Buffer.alloc(4);
	crc.writeUInt32BE(crc32(td));
	return Buffer.concat([len, td, crc]);
}

/** A small solid PNG, so the browser has something real to decode. */
function png(width: number, height: number): Buffer {
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(width, 0);
	ihdr.writeUInt32BE(height, 4);
	ihdr[8] = 8;
	ihdr[9] = 2;
	const row = Buffer.concat([Buffer.from([0]), Buffer.alloc(width * 3, 0x80)]);
	const raw = Buffer.concat(Array.from({ length: height }, () => row));
	return Buffer.concat([
		Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
		chunk('IHDR', ihdr),
		chunk('IDAT', deflateSync(raw)),
		chunk('IEND', Buffer.alloc(0))
	]);
}

async function openAs(browser: Browser, user: SagaUser): Promise<{ page: Page; close: () => Promise<void> }> {
	const ctx = await browser.newContext({ storageState: user.storageStatePath });
	await acceptCookieConsent(ctx);
	const page = await ctx.newPage();
	return { page, close: () => ctx.close() };
}

test.describe('/messages — photos and links', () => {
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[] = [];

	test.afterEach(async () => {
		if (users.length > 0) await deleteSagaUsers(users);
		users = [];
	});

	async function pair(stamp: string) {
		users = await createSagaUsers(2, { displayNames: [`Sender ${stamp}`, `Viewer ${stamp}`] });
		const [sender, viewer] = users;
		const { error } = await getAdminClient()
			.from('user_follows')
			.insert({ follower_id: sender.id, followee_id: viewer.id });
		if (error) throw new Error(`follow seed failed: ${error.message}`);
		return { sender, viewer };
	}

	test('a link shows its domain chip and opens safely, and markup stays text', async ({ browser }) => {
		const stamp = Date.now().toString(36);
		const { sender, viewer } = await pair(stamp);
		const { error } = await getAdminClient().from('direct_messages').insert({
			sender_id: sender.id,
			recipient_id: viewer.id,
			body: `route <b>${stamp}</b> https://www.example.com/route/1, and https://evil@bad.example/x`
		});
		if (error) throw new Error(`message seed failed: ${error.message}`);

		const v = await openAs(browser, viewer);
		try {
			await v.page.goto(`/messages/${sender.id}`);
			const bubble = v.page.getByTestId('dm-bubble').filter({ hasText: stamp });
			await expect(bubble).toBeVisible({ timeout: 10_000 });
			await expect(bubble).toContainText(`<b>${stamp}</b>`);
			await expect(bubble.locator('b')).toHaveCount(0);
			const link = bubble.getByTestId('dm-link');
			await expect(link).toHaveCount(1);
			await expect(link).toHaveAttribute('href', 'https://www.example.com/route/1');
			await expect(link).toHaveAttribute('rel', 'noopener noreferrer nofollow ugc');
			await expect(link).toHaveAttribute('target', '_blank');
			await expect(bubble.getByTestId('dm-link-domain')).toHaveText(/example\.com/);
		} finally {
			await v.close();
		}
	});

	test('a photo is sent, waits for the server copy, then shows from a signed URL', async ({ browser }) => {
		const stamp = Date.now().toString(36);
		const { sender, viewer } = await pair(stamp);
		const admin = getAdminClient();

		const s = await openAs(browser, sender);
		try {
			await s.page.goto(`/messages/${viewer.id}`);
			await expect(s.page.getByTestId('dm-attach-photo')).toBeVisible({ timeout: 10_000 });
			await s.page.getByTestId('dm-photo-input').setInputFiles({
				name: 'track.png',
				mimeType: 'image/png',
				buffer: png(40, 30)
			});
			await expect(s.page.getByTestId('dm-photo-draft')).toBeVisible();
			await s.page.getByRole('button', { name: 'Send', exact: true }).click();
			await expect(s.page.getByTestId('dm-photo-pending')).toBeVisible({ timeout: 10_000 });
			await expect(s.page.getByTestId('dm-bubble').filter({ hasText: 'Message unsent' })).toHaveCount(0);
		} finally {
			await s.close();
		}

		const image = await readMaybeRow(
			'the sent image',
			admin
				.from('direct_message_images')
				.select('id, owner_id, status, upload_path, storage_path, message_id')
				.eq('owner_id', sender.id)
				.maybeSingle()
		);
		expect(image).not.toBeNull();
		expect(image!.status).toBe('pending');
		expect(image!.message_id).not.toBeNull();
		expect(image!.upload_path).toBe(`${sender.id}/${image!.id}/upload`);

		const { data: upload, error: downloadError } = await admin.storage.from('dm-images').download(image!.upload_path);
		if (downloadError || !upload) throw new Error(`upload missing: ${downloadError?.message}`);
		const bytes = Buffer.from(await upload.arrayBuffer());
		expect(bytes.subarray(0, 2).toString('hex')).toBe('ffd8');
		expect(bytes.includes(Buffer.from('Exif'))).toBe(false);

		const { error: putError } = await admin.storage
			.from('dm-images')
			.upload(image!.storage_path, bytes, { contentType: 'image/jpeg', upsert: true });
		if (putError) throw new Error(`stand-in re-encode failed: ${putError.message}`);
		const { error: readyError } = await admin
			.from('direct_message_images')
			.update({ status: 'ready', width: 40, height: 30, processed_at: new Date().toISOString() })
			.eq('id', image!.id);
		if (readyError) throw new Error(`mark ready failed: ${readyError.message}`);

		const v = await openAs(browser, viewer);
		try {
			await v.page.goto(`/messages/${sender.id}`);
			const img = v.page.getByTestId('dm-photo').locator('img');
			await expect(img).toBeVisible({ timeout: 10_000 });
			await expect(img).toHaveAttribute('src', /\/object\/sign\/dm-images\//);
		} finally {
			await v.close();
		}
	});

	test('message requests can be switched off in Settings and the choice persists', async ({ browser }) => {
		const stamp = Date.now().toString(36);
		users = await createSagaUsers(1, { displayNames: [`Quiet ${stamp}`] });
		const [quiet] = users;
		const q = await openAs(browser, quiet);
		try {
			await q.page.goto('/settings/privacy');
			const toggle = q.page.getByTestId('message-requests-toggle');
			await expect(toggle).toBeChecked({ timeout: 10_000 });
			await toggle.uncheck();
			await expect
				.poll(async () =>
					(
						await readMaybeRow(
							'settings',
							getAdminClient().from('user_settings').select('dm_requests').eq('user_id', quiet.id).maybeSingle()
						)
					)?.dm_requests
				)
				.toBe(false);
			await q.page.reload();
			await expect(q.page.getByTestId('message-requests-toggle')).not.toBeChecked({ timeout: 10_000 });
		} finally {
			await q.close();
		}
	});
});
