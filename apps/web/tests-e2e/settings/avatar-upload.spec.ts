import { expect, test, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_C_PRO } from '../fixtures/users';
import { readMaybeRow, readRow } from '../fixtures/db-read';

/**
 * Avatar upload — the in-app profile-picture feature (AvatarCropDialog →
 * data.ts uploadAvatar / removeAvatar → the public `avatars` Storage bucket,
 * migration 20260927_001).
 *
 *   1. USER_A picks a landscape PNG in /settings/account; the crop dialog
 *      opens, they rotate it left and confirm. Only the cropped square is
 *      uploaded, re-encoded as {uid}/avatar.jpg; the stored pixels show the
 *      turn (the source's right half on top).
 *   2. Cancelling the crop step with Escape uploads nothing.
 *   3. The owner's /u/[id] profile renders the <img>, and a second user
 *      (USER_C_PRO) sees the same avatar — it's public.
 *   4. A geotagged JPEG stored sideways with EXIF Orientation 6 arrives
 *      upright without the user touching rotate, and the stored object has no
 *      "Exif" bytes — the re-encode drops the GPS with the rest of the APP1.
 *   5. Remove is confirmed, then clears avatar_url and deletes the objects.
 *
 * USER_A's avatar_url is shared seed state, so the original value is captured
 * up front and restored in `finally` (with a sweep of any object we created).
 */

// A source image whose halves are told apart after a crop: red on the left,
// blue on the right, 40x20, encoded by the browser so it decodes everywhere.
async function twoToneImage(page: Page, type: 'image/png' | 'image/jpeg'): Promise<Buffer> {
	const dataUrl = await page.evaluate((mime) => {
		const c = document.createElement('canvas');
		c.width = 40;
		c.height = 20;
		const ctx = c.getContext('2d')!;
		ctx.fillStyle = '#ff0000';
		ctx.fillRect(0, 0, 20, 20);
		ctx.fillStyle = '#0000ff';
		ctx.fillRect(20, 0, 20, 20);
		return c.toDataURL(mime, 1);
	}, type);
	return Buffer.from(dataUrl.split(',')[1], 'base64');
}

// Splice an APP1 "Exif" segment straight after SOI: IFD0 carries one entry,
// Orientation = 6 (display rotated 90 degrees clockwise), followed by filler
// standing in for a GPS IFD.
function withExifOrientation6(jpeg: Buffer): Buffer {
	const tiff = Buffer.from([
		0x49, 0x49, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00,
		0x01, 0x00,
		0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00,
	]);
	const payload = Buffer.concat([
		Buffer.from('Exif\0\0', 'latin1'),
		tiff,
		Buffer.from('GPS-FILLER', 'latin1'),
	]);
	const len = payload.length + 2;
	const app1 = Buffer.concat([Buffer.from([0xff, 0xe1, (len >> 8) & 0xff, len & 0xff]), payload]);
	return Buffer.concat([jpeg.subarray(0, 2), app1, jpeg.subarray(2)]);
}

type Rgb = [number, number, number];

// Decode stored bytes in the browser; read the centre column a quarter of the
// way down and a quarter of the way up, plus the decoded size.
async function sample(
	page: Page,
	bytes: Buffer,
): Promise<{ w: number; h: number; top: Rgb; bottom: Rgb }> {
	return page.evaluate(async (b64) => {
		const bin = Uint8Array.from(atob(b64), (ch) => ch.charCodeAt(0));
		const bmp = await createImageBitmap(new Blob([bin]));
		const c = document.createElement('canvas');
		c.width = bmp.width;
		c.height = bmp.height;
		const ctx = c.getContext('2d')!;
		ctx.drawImage(bmp, 0, 0);
		const px = (y: number): [number, number, number] => {
			const d = ctx.getImageData(Math.floor(bmp.width / 2), y, 1, 1).data;
			return [d[0], d[1], d[2]];
		};
		return {
			w: bmp.width,
			h: bmp.height,
			top: px(Math.floor(bmp.height / 4)),
			bottom: px(Math.floor((bmp.height * 3) / 4)),
		};
	}, bytes.toString('base64'));
}

const isRed = ([r, , b]: Rgb) => r > 180 && b < 80;
const isBlue = ([r, , b]: Rgb) => b > 180 && r < 80;

const decodes = (img: HTMLImageElement) => img.complete && img.naturalWidth > 0;

test.describe('avatar upload', () => {
	test.describe.configure({ timeout: 90_000 });
	test.use({ storageState: USER_A.storageStatePath });

	test('crop + rotate before upload → others see it → EXIF orientation honoured and stripped → remove', async ({
		page,
		browser,
	}) => {
		const admin = getAdminClient();
		const objectPaths = ['jpg', 'png', 'webp'].map((e) => `${USER_A.id}/avatar.${e}`);
		// Service-role list bypasses RLS — the robust way to assert which objects
		// actually exist for the user (download-of-missing isn't reliably null).
		const avatarNames = async (): Promise<string[]> => {
			const { data } = await admin.storage.from('avatars').list(USER_A.id);
			return (data ?? []).map((i) => i.name);
		};
		const storedAvatar = async (): Promise<Buffer> => {
			const dl = await readMaybeRow(
				'avatars',
				admin.storage.from('avatars').download(`${USER_A.id}/avatar.jpg`),
			);
			expect(dl).toBeTruthy();
			return Buffer.from(await dl!.arrayBuffer());
		};
		const storedUrl = async (): Promise<string> => {
			const row = await readRow(
				'user_profiles by id',
				admin.from('user_profiles').select('avatar_url').eq('id', USER_A.id).single(),
			);
			return String(row.avatar_url ?? '');
		};

		const { data: before } = await admin
			.from('user_profiles')
			.select('avatar_url')
			.eq('id', USER_A.id)
			.single();
		const originalAvatar = (before?.avatar_url as string | null) ?? null;

		try {
			await test.step('USER_A picks a PNG, rotates it left in the crop step, and confirms', async () => {
				await page.goto('/settings/account');
				await page.getByTestId('avatar-change').waitFor({ timeout: 10_000 });
				const png = await twoToneImage(page, 'image/png');
				await page
					.getByTestId('avatar-file-input')
					.setInputFiles({ name: 'me.png', mimeType: 'image/png', buffer: png });

				const dialog = page.getByTestId('avatar-crop-dialog');
				await expect(dialog).toBeVisible();
				await expect(dialog.getByRole('button', { name: 'Use photo' })).toBeEnabled({
					timeout: 10_000,
				});
				await dialog.getByRole('button', { name: 'Rotate left' }).click();
				await dialog.getByRole('button', { name: 'Use photo' }).click();
				await expect(dialog).toHaveCount(0);
				await expect(page.locator('.toast-success')).toContainText(/updated/i, {
					timeout: 10_000,
				});

				expect(await storedUrl()).toMatch(
					/\/storage\/v1\/object\/public\/avatars\/.*\/avatar\.jpg\?v=\d+/,
				);
				expect(await avatarNames()).toEqual(['avatar.jpg']);

				// The 20 px centre square of the turned 20x40 image: a counter-
				// clockwise turn puts the source's right (blue) half on top.
				const out = await sample(page, await storedAvatar());
				expect([out.w, out.h]).toEqual([20, 20]);
				expect(isBlue(out.top), `top ${out.top}`).toBe(true);
				expect(isRed(out.bottom), `bottom ${out.bottom}`).toBe(true);
			});

			await test.step('cancelling the crop step with Escape uploads nothing', async () => {
				const urlBefore = await storedUrl();
				const png = await twoToneImage(page, 'image/png');
				await page
					.getByTestId('avatar-file-input')
					.setInputFiles({ name: 'other.png', mimeType: 'image/png', buffer: png });
				const dialog = page.getByTestId('avatar-crop-dialog');
				await expect(dialog).toBeVisible();
				await page.keyboard.press('Escape');
				await expect(dialog).toHaveCount(0);
				expect(await storedUrl()).toBe(urlBefore);
			});

			await test.step("the owner's /u/[id] and a second user both show the avatar", async () => {
				// The settings <Avatar> only renders https URLs (safeImageSrc), and
				// the local stack serves http, so the profile page is where the
				// freshly uploaded, cache-busted URL is observable.
				await page.goto(`/u/${USER_A.id}`);
				const img = page.locator('.avatar-xl img');
				await expect(img).toBeVisible({ timeout: 10_000 });
				await expect(img).toHaveAttribute('src', await storedUrl());
				await expect.poll(async () => img.evaluate(decodes), { timeout: 10_000 }).toBe(true);

				const ctx = await browser.newContext({ storageState: USER_C_PRO.storageStatePath });
				const guest = await ctx.newPage();
				try {
					await guest.goto(`/u/${USER_A.id}`);
					const guestImg = guest.locator('.avatar-xl img');
					await expect(guestImg).toBeVisible({ timeout: 10_000 });
					await expect
						.poll(async () => guestImg.evaluate(decodes), { timeout: 10_000 })
						.toBe(true);
				} finally {
					await ctx.close();
				}
			});

			await test.step('a sideways geotagged JPEG arrives upright with its EXIF gone', async () => {
				await page.goto('/settings/account');
				await page.getByTestId('avatar-change').waitFor({ timeout: 10_000 });
				const jpeg = withExifOrientation6(await twoToneImage(page, 'image/jpeg'));
				await page
					.getByTestId('avatar-file-input')
					.setInputFiles({ name: 'geo.jpg', mimeType: 'image/jpeg', buffer: jpeg });
				const dialog = page.getByTestId('avatar-crop-dialog');
				const confirm = dialog.getByRole('button', { name: 'Use photo' });
				await expect(confirm).toBeEnabled({ timeout: 10_000 });
				await confirm.click();
				await expect(page.locator('.toast-success')).toContainText(/updated/i, {
					timeout: 10_000,
				});

				const bytes = await storedAvatar();
				expect(bytes.includes(Buffer.from('Exif', 'latin1'))).toBe(false);
				expect(bytes.includes(Buffer.from('GPS-FILLER', 'latin1'))).toBe(false);
				// Orientation 6 turns the stored 40x20 clockwise, so its left (red)
				// half is on top once decoded upright; ignoring the tag would
				// leave the centre crop split left/right instead.
				const out = await sample(page, bytes);
				expect([out.w, out.h]).toEqual([20, 20]);
				expect(isRed(out.top), `top ${out.top}`).toBe(true);
				expect(isBlue(out.bottom), `bottom ${out.bottom}`).toBe(true);
			});

			await test.step('cancelling the remove confirm keeps the avatar', async () => {
				await page.goto('/settings/account');
				await page.getByTestId('avatar-remove').click();
				const dialog = page.locator('.modal', { hasText: 'Remove profile photo?' });
				await expect(dialog).toBeVisible({ timeout: 10_000 });
				await dialog.getByRole('button', { name: 'Cancel' }).click();
				await expect(dialog).toHaveCount(0);

				// The Storage object is untouched — the delete is not recoverable,
				// so a cancel has to mean nothing happened.
				expect(await avatarNames()).toContain('avatar.jpg');
			});

			await test.step('USER_A removes the avatar', async () => {
				await page.getByTestId('avatar-remove').click();
				const dialog = page.locator('.modal', { hasText: 'Remove profile photo?' });
				await expect(dialog).toBeVisible({ timeout: 10_000 });
				await dialog.getByRole('button', { name: 'Remove', exact: true }).click();
				await expect(page.locator('.toast-success')).toContainText(/removed/i, {
					timeout: 10_000,
				});
				expect(await storedUrl()).toBe('');
				expect(await avatarNames()).toHaveLength(0);
			});
		} finally {
			await admin
				.from('user_profiles')
				.update({ avatar_url: originalAvatar })
				.eq('id', USER_A.id);
			await admin.storage.from('avatars').remove(objectPaths);
		}
	});
});
