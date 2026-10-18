import type { Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteClub } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';
import { readRow, readRows } from '../fixtures/db-read';

/**
 * Club logo — an owner sets the picture behind `clubs.avatar_url`
 * (ClubLogoControl → uploadClubLogo / removeClubLogo → the public `avatars`
 * bucket at clubs/{club_id}/logo.{ext}, migration 20270918000007).
 *
 *   1. USER_A (owner) picks a PNG on the club page, confirms the crop, and the
 *      header circle and the club's card on /clubs both show the stored logo.
 *   2. USER_B (an active member) sees the logo but no logo control.
 *   3. Remove is confirmed, then clears avatar_url and the header falls back
 *      to the initial.
 */

const LOGO_PATHS = (clubId: string) =>
	['jpg', 'png', 'webp'].map((e) => `clubs/${clubId}/logo.${e}`);

async function solidPng(page: Page): Promise<Buffer> {
	const dataUrl = await page.evaluate(() => {
		const c = document.createElement('canvas');
		c.width = 32;
		c.height = 32;
		const ctx = c.getContext('2d')!;
		ctx.fillStyle = '#00aa55';
		ctx.fillRect(0, 0, 32, 32);
		return c.toDataURL('image/png');
	});
	return Buffer.from(dataUrl.split(',')[1], 'base64');
}

test.describe('/clubs/[slug] — club logo', () => {
	test.describe.configure({ timeout: 90_000 });
	test.use({ storageState: USER_A.storageStatePath });

	let clubId: string | null = null;

	test.afterEach(async () => {
		if (!clubId) return;
		const admin = getAdminClient();
		try {
			await admin.storage.from('avatars').remove(LOGO_PATHS(clubId));
			await deleteClub(clubId);
		} catch (_) {
			/* best-effort */
		}
		clubId = null;
	});

	test('owner uploads a logo, header + list card show it, a member gets no control, remove confirms', async ({
		page,
		browser,
	}) => {
		const admin = getAdminClient();
		const id = crypto.randomUUID();
		const slug = `e2e-logo-${id.slice(0, 8)}`;
		const name = `E2E Logo Club ${id.slice(0, 6)}`;
		const inserted = await admin
			.from('clubs')
			.insert({ id, owner_id: USER_A.id, name, slug, is_public: true });
		if (inserted.error) throw new Error(`club insert failed: ${inserted.error.message}`);
		clubId = id;
		const joined = await admin
			.from('club_members')
			.insert({ club_id: id, user_id: USER_B.id, role: 'member', status: 'active' });
		if (joined.error) throw new Error(`member insert failed: ${joined.error.message}`);

		const storedUrl = async (): Promise<string | null> => {
			const row = await readRow(
				'clubs by id',
				admin.from('clubs').select('avatar_url').eq('id', id).single(),
			);
			return (row.avatar_url as string | null) ?? null;
		};

		const headerAvatar = page.locator('.hero').getByTestId('club-avatar');

		await test.step('owner uploads a logo', async () => {
			await page.goto(`/clubs/${slug}`);
			await expect(page.getByRole('heading', { level: 1, name })).toBeVisible({
				timeout: 10_000,
			});
			await expect(headerAvatar).toHaveAttribute('data-has-logo', 'false');
			await expect(page.getByTestId('club-logo-remove')).toHaveCount(0);

			await page
				.getByTestId('club-logo-file-input')
				.setInputFiles({ name: 'logo.png', mimeType: 'image/png', buffer: await solidPng(page) });
			const dialog = page.getByTestId('avatar-crop-dialog');
			await expect(dialog).toBeVisible();
			await expect(dialog.getByRole('heading', { name: 'Adjust club logo' })).toBeVisible();
			await expect(dialog.getByRole('button', { name: 'Use photo' })).toBeEnabled({
				timeout: 10_000,
			});
			await dialog.getByRole('button', { name: 'Use photo' }).click();
			await expect(dialog).toHaveCount(0);
			await expect(page.locator('.toast-success')).toContainText('Club logo updated.', {
				timeout: 10_000,
			});

			const url = await storedUrl();
			expect(url).toMatch(
				new RegExp(`/storage/v1/object/public/avatars/clubs/${id}/logo\\.jpg\\?v=\\d+$`),
			);
			const objects = await readRows(
				'club logo objects',
				admin.storage.from('avatars').list(`clubs/${id}`),
			);
			expect(objects.map((o) => o.name)).toEqual(['logo.jpg']);
			await expect(headerAvatar).toHaveAttribute('data-has-logo', 'true');
			await expect(headerAvatar.locator('img')).toHaveAttribute('src', url!);
		});

		await test.step('the club card on /clubs shows the logo', async () => {
			await page.goto('/clubs');
			const card = page.locator('a.card', { has: page.getByRole('heading', { name }) });
			await expect(card).toBeVisible({ timeout: 10_000 });
			const cardAvatar = card.getByTestId('club-avatar');
			await expect(cardAvatar).toHaveAttribute('data-has-logo', 'true');
			await expect(cardAvatar.locator('img')).toHaveAttribute('src', (await storedUrl())!);
		});

		await test.step('a member sees the logo but no logo control', async () => {
			const ctx = await browser.newContext({ storageState: USER_B.storageStatePath });
			const member = await ctx.newPage();
			try {
				await member.goto(`/clubs/${slug}`);
				await expect(member.getByRole('heading', { level: 1, name })).toBeVisible({
					timeout: 10_000,
				});
				await expect(member.locator('.hero').getByTestId('club-avatar')).toHaveAttribute(
					'data-has-logo',
					'true',
				);
				await expect(member.getByTestId('club-logo-control')).toHaveCount(0);
			} finally {
				await ctx.close();
			}
		});

		await test.step('owner removes the logo after confirming', async () => {
			await page.goto(`/clubs/${slug}`);
			await page.getByTestId('club-logo-remove').click();
			const confirm = page.getByRole('dialog', { name: 'Remove club logo?' });
			await expect(confirm).toBeVisible();
			await confirm.getByRole('button', { name: 'Remove logo' }).click();
			await expect(page.locator('.toast-success')).toContainText('Club logo removed.', {
				timeout: 10_000,
			});
			await expect(headerAvatar).toHaveAttribute('data-has-logo', 'false');
			expect(await storedUrl()).toBeNull();
			const remaining = await readRows(
				'club logo objects',
				admin.storage.from('avatars').list(`clubs/${id}`),
			);
			expect(remaining.map((o) => o.name)).toEqual([]);
		});
	});
});
