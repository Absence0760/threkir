import { expect, test } from '../fixtures/test';

import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteClub } from '../fixtures/simulate';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * A user's uploaded avatar reaches the surfaces that show who they are, not
 * only their /u profile. The club Members row and the sidebar account button
 * (plus its menu) each rendered the initial unconditionally while the data
 * already carried `avatar_url` — the roster query selected it, the auth store
 * held it — so a new member who had uploaded a photo still showed a coloured
 * "T". `user_avatar_guard.test.ts` holds every other <Avatar> site to the same
 * rule at the source level; this pins the two surfaces the report named in a
 * real browser.
 *
 * A saga user rather than the shared seed user: setting `avatar_url` on
 * USER_A would flip the initial-placeholder assertions in avatar.spec.ts for
 * any spec running beside this one. The URL is https:// because both the
 * `user_profiles_avatar_url_scheme` CHECK and safeImageSrc require it, and its
 * bytes are routed locally so nothing resolves the host.
 */

const PNG_1x1 = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
	'base64',
);

const suffix = () => `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('user avatar on identity surfaces', () => {
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[];

	test.beforeAll(async () => {
		users = await createSagaUsers(1, { displayNames: ['Tess Avatar'] });
	});

	test.afterAll(async () => {
		await deleteSagaUsers(users);
	});

	test('the club Members row and the sidebar account menu show the uploaded image', async ({
		browser,
	}) => {
		const [me] = users;
		const avatarUrl = `https://e2e-avatars.invalid/${me.id}-${suffix()}.png`;
		const admin = getAdminClient();
		let clubId: string | null = null;

		const { error: avatarErr } = await admin
			.from('user_profiles')
			.update({ avatar_url: avatarUrl })
			.eq('id', me.id);
		if (avatarErr) throw new Error(`avatar seed failed: ${avatarErr.message}`);

		const ctx = await browser.newContext({ storageState: me.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		await page.route(avatarUrl, (route) =>
			route.fulfill({ contentType: 'image/png', body: PNG_1x1 }),
		);

		try {
			// The enroll_club_owner_trigger seats the owner's club_members row,
			// so the owner is the one member the roster is guaranteed to show.
			const slug = `avatar-club-${suffix()}`;
			const clubName = `Avatar Club ${suffix()}`;
			const { data: club, error: clubErr } = await admin
				.from('clubs')
				.insert({ owner_id: me.id, name: clubName, slug, is_public: true })
				.select('id')
				.single();
			if (clubErr || !club) throw new Error(`club seed failed: ${clubErr?.message ?? 'no row'}`);
			clubId = club.id as string;

			await test.step('the Members tab row renders the avatar image', async () => {
				await page.goto(`/clubs/${slug}`);
				await expect(page.getByRole('heading', { level: 1, name: clubName })).toBeVisible({
					timeout: 10_000,
				});
				await page.getByRole('tab', { name: /^Members/ }).click();
				const row = page.locator('.member-list .member', { hasText: 'Tess Avatar' });
				await expect(row).toBeVisible({ timeout: 10_000 });
				await expect(row.locator('img')).toHaveAttribute('src', avatarUrl);
				await expect(row.getByText('T', { exact: true })).toHaveCount(0);
			});

			await test.step('the sidebar account button renders the avatar image', async () => {
				const sidebarImg = page.getByTestId('sidebar-avatar').locator('img');
				await expect(sidebarImg).toHaveAttribute('src', avatarUrl, { timeout: 10_000 });
			});

			await test.step('the account menu header renders the avatar image', async () => {
				await page.locator('.profile-btn').click();
				const menuImg = page.getByTestId('account-menu-avatar').locator('img');
				await expect(menuImg).toHaveAttribute('src', avatarUrl, { timeout: 5_000 });
			});
		} finally {
			if (clubId) {
				try {
					await deleteClub(clubId);
				} catch (_) {
					/* best-effort; deleteSagaUsers also sweeps owner clubs */
				}
			}
			await ctx.close();
		}
	});
});
