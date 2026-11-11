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

/** A small solid PNG, so the browser has something real to decode; `clear` makes every pixel fully transparent. */
function png(width: number, height: number, clear = false): Buffer {
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(width, 0);
	ihdr.writeUInt32BE(height, 4);
	ihdr[8] = 8;
	ihdr[9] = clear ? 6 : 2;
	const row = Buffer.concat([Buffer.from([0]), clear ? Buffer.alloc(width * 4, 0) : Buffer.alloc(width * 3, 0x80)]);
	const raw = Buffer.concat(Array.from({ length: height }, () => row));
	return Buffer.concat([
		Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
		chunk('IHDR', ihdr),
		chunk('IDAT', deflateSync(raw)),
		chunk('IEND', Buffer.alloc(0))
	]);
}

/**
 * A camera-style EXIF block: orientation 6 (the pixels are stored a quarter
 * turn round) and a GPS latitude, big-endian, as an APP1 segment.
 */
function exifApp1(): Buffer {
	const tiff = Buffer.alloc(92);
	tiff.write('MM', 0, 'ascii');
	tiff.writeUInt16BE(42, 2);
	tiff.writeUInt32BE(8, 4);
	tiff.writeUInt16BE(2, 8);
	tiff.writeUInt16BE(0x0112, 10);
	tiff.writeUInt16BE(3, 12);
	tiff.writeUInt32BE(1, 14);
	tiff.writeUInt16BE(6, 18);
	tiff.writeUInt16BE(0x8825, 22);
	tiff.writeUInt16BE(4, 24);
	tiff.writeUInt32BE(1, 26);
	tiff.writeUInt32BE(38, 30);
	tiff.writeUInt16BE(2, 38);
	tiff.writeUInt16BE(0x0001, 40);
	tiff.writeUInt16BE(2, 42);
	tiff.writeUInt32BE(2, 44);
	tiff.write('N', 48, 'ascii');
	tiff.writeUInt16BE(0x0002, 52);
	tiff.writeUInt16BE(5, 54);
	tiff.writeUInt32BE(3, 56);
	tiff.writeUInt32BE(68, 60);
	[51, 30, 2].forEach((v, k) => {
		tiff.writeUInt32BE(v, 68 + k * 8);
		tiff.writeUInt32BE(1, 72 + k * 8);
	});
	const payload = Buffer.concat([Buffer.from('Exif\0\0', 'binary'), tiff]);
	const head = Buffer.from([0xff, 0xe1, 0, 0]);
	head.writeUInt16BE(payload.length + 2, 2);
	return Buffer.concat([head, payload]);
}

/** The marker of every JPEG segment before the scan, and the frame size its SOF declares. */
function jpegHeader(jpeg: Buffer): { markers: number[]; width: number; height: number } {
	const markers: number[] = [];
	let width = 0;
	let height = 0;
	let i = 2;
	while (i + 3 < jpeg.length && jpeg[i] === 0xff) {
		const marker = jpeg[i + 1];
		markers.push(marker);
		if (marker === 0xda) break;
		if (marker >= 0xc0 && marker <= 0xc2) {
			height = jpeg.readUInt16BE(i + 5);
			width = jpeg.readUInt16BE(i + 7);
		}
		i += 2 + jpeg.readUInt16BE(i + 2);
	}
	return { markers, width, height };
}

/** The bytes of the composer's draft: what the browser re-encoded and would upload. */
async function draftBytes(page: Page): Promise<Buffer> {
	const draft = page.getByTestId('dm-photo-draft').locator('img');
	await expect(draft).toBeVisible({ timeout: 10_000 });
	const src = await draft.getAttribute('src');
	const bytes = await page.evaluate(async (url) => Array.from(new Uint8Array(await (await fetch(url!)).arrayBuffer())), src);
	return Buffer.from(bytes);
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

	test('the browser re-encode drops EXIF and GPS, bakes the orientation, flattens onto white and refuses a GIF', async ({ browser }) => {
		const stamp = Date.now().toString(36);
		const { sender, viewer } = await pair(stamp);
		const s = await openAs(browser, sender);
		try {
			await s.page.goto(`/messages/${viewer.id}`);
			await expect(s.page.getByTestId('dm-attach-photo')).toBeVisible({ timeout: 10_000 });
			const input = s.page.getByTestId('dm-photo-input');

			const plain = Buffer.from(
				await s.page.evaluate(async () => {
					const c = document.createElement('canvas');
					c.width = 300;
					c.height = 100;
					const ctx = c.getContext('2d')!;
					ctx.fillStyle = '#c82828';
					ctx.fillRect(0, 0, 300, 100);
					const blob = await new Promise<Blob>((r) => c.toBlob((b) => r(b!), 'image/jpeg', 0.9));
					return Array.from(new Uint8Array(await blob.arrayBuffer()));
				})
			);
			const geotagged = Buffer.concat([plain.subarray(0, 2), exifApp1(), plain.subarray(2)]);
			expect(jpegHeader(geotagged).markers).toContain(0xe1);
			expect(geotagged.includes(Buffer.from('Exif'))).toBe(true);

			await input.setInputFiles({ name: 'IMG_0001.jpg', mimeType: 'image/jpeg', buffer: geotagged });
			const out = await draftBytes(s.page);
			const header = jpegHeader(out);
			expect(out.subarray(0, 3).toString('hex')).toBe('ffd8ff');
			expect(header.markers).not.toContain(0xe1);
			expect(out.includes(Buffer.from('Exif'))).toBe(false);
			expect({ width: header.width, height: header.height }, 'orientation 6 is baked into the pixels').toEqual({
				width: 100,
				height: 300
			});
			await s.page.getByTestId('dm-photo-remove').click();
			await expect(s.page.getByTestId('dm-photo-draft')).toHaveCount(0);

			await input.setInputFiles({ name: 'clear.png', mimeType: 'image/png', buffer: png(20, 20, true) });
			const flat = await draftBytes(s.page);
			const pixel = await s.page.evaluate(async (bytes) => {
				const bitmap = await createImageBitmap(new Blob([new Uint8Array(bytes)], { type: 'image/jpeg' }));
				const c = document.createElement('canvas');
				c.width = bitmap.width;
				c.height = bitmap.height;
				const ctx = c.getContext('2d')!;
				ctx.drawImage(bitmap, 0, 0);
				return Array.from(ctx.getImageData(10, 10, 1, 1).data);
			}, Array.from(flat));
			for (const channel of pixel.slice(0, 3)) expect(channel, `pixel ${pixel} is white, not black`).toBeGreaterThan(245);
			await s.page.getByTestId('dm-photo-remove').click();

			const gif = Buffer.from('R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==', 'base64');
			await input.setInputFiles({ name: 'loop.gif', mimeType: 'image/gif', buffer: gif });
			await expect(s.page.getByRole('alert').filter({ hasText: "That file couldn't be read as a photo." })).toBeVisible();
			await expect(s.page.getByTestId('dm-photo-draft')).toHaveCount(0);
		} finally {
			await s.close();
		}
	});

	/** A photo message from `sender`, as the send leaves it: the image row pending and linked. */
	async function seedPhotoMessage(sender: SagaUser, viewer: SagaUser, caption: string) {
		const admin = getAdminClient();
		const id = crypto.randomUUID();
		const { error: imageError } = await admin.from('direct_message_images').insert({
			id,
			owner_id: sender.id,
			upload_path: `${sender.id}/${id}/upload`,
			storage_path: `${sender.id}/${id}.jpg`
		});
		if (imageError) throw new Error(`image seed failed: ${imageError.message}`);
		const { data, error } = await admin
			.from('direct_messages')
			.insert({ sender_id: sender.id, recipient_id: viewer.id, body: caption, image_id: id })
			.select('id')
			.single();
		if (error || !data) throw new Error(`message seed failed: ${error?.message}`);
		return { imageId: id, messageId: data.id };
	}

	test('a photo the server refused reads as not sent, to both sides, with no image', async ({ browser }) => {
		const stamp = Date.now().toString(36);
		const { sender, viewer } = await pair(stamp);
		const { imageId } = await seedPhotoMessage(sender, viewer, `refused ${stamp}`);
		const { error } = await getAdminClient()
			.from('direct_message_images')
			.update({ status: 'rejected', processed_at: new Date().toISOString() })
			.eq('id', imageId);
		if (error) throw new Error(`reject failed: ${error.message}`);

		for (const [me, partner] of [
			[sender, viewer],
			[viewer, sender]
		] as const) {
			const c = await openAs(browser, me);
			try {
				await c.page.goto(`/messages/${partner.id}`);
				const bubble = c.page.getByTestId('dm-bubble').filter({ hasText: `refused ${stamp}` });
				await expect(bubble.getByTestId('dm-photo-rejected')).toHaveText("This photo couldn't be sent.", {
					timeout: 10_000
				});
				await expect(bubble.getByTestId('dm-photo')).toHaveCount(0);
				await expect(bubble.getByTestId('dm-photo-pending')).toHaveCount(0);
			} finally {
				await c.close();
			}
		}
	});

	test('a photo whose image was erased reads as unavailable, not as still preparing', async ({ browser }) => {
		const stamp = Date.now().toString(36);
		const { sender, viewer } = await pair(stamp);
		const { imageId, messageId } = await seedPhotoMessage(sender, viewer, `erased ${stamp}`);
		const admin = getAdminClient();
		const { error } = await admin.from('direct_message_images').delete().eq('id', imageId);
		if (error) throw new Error(`erase failed: ${error.message}`);
		const message = await readMaybeRow(
			'the photo message',
			admin.from('direct_messages').select('image_id').eq('id', messageId).maybeSingle()
		);
		expect(message?.image_id, 'the message still names the image it carried').toBe(imageId);

		const v = await openAs(browser, viewer);
		try {
			await v.page.goto(`/messages/${sender.id}`);
			const bubble = v.page.getByTestId('dm-bubble').filter({ hasText: `erased ${stamp}` });
			await expect(bubble.getByTestId('dm-photo-unavailable')).toHaveText('Photo unavailable', { timeout: 10_000 });
			await expect(bubble.getByTestId('dm-photo-pending')).toHaveCount(0);
			await expect(bubble.getByTestId('dm-photo')).toHaveCount(0);
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
