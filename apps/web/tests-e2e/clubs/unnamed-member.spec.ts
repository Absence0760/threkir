import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { readRow } from '../fixtures/db-read';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * A club member with no display name (issue #1300 BUG-013, decisions § 2365).
 *
 * The roster used to show "Member" with a "?" avatar, so several unnamed
 * people were indistinguishable and the person never learned why. The roster
 * now shows the localised runnerHandle (`Runner #A1B2`), and the member is
 * told how others see them, with a link to add a name.
 */

test.describe('/clubs/[slug] — a member with no display name', () => {
	let user: SagaUser;
	let handle: string;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1);
		const admin = getAdminClient();
		await admin.from('user_profiles').update({ display_name: null }).eq('id', user.id);
		const club = await readRow(
			'clubs by slug',
			admin.from('clubs').select('id').eq('slug', 'richmond-run-club').maybeSingle(),
		);
		const { error } = await admin
			.from('club_members')
			.insert({ club_id: club.id, user_id: user.id, role: 'member', status: 'active' });
		if (error) throw new Error(`club_members insert: ${error.message}`);
		handle = `Runner #${user.id.replace(/-/g, '').slice(0, 4).toUpperCase()}`;
	});

	test.afterAll(async () => {
		if (user) await deleteSagaUsers([user]);
	});

	test('the roster shows their handle and they are told how to add a name', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto('/clubs/richmond-run-club');
			const hint = page.getByTestId('club-name-hint');
			await expect(hint).toBeVisible({ timeout: 10_000 });
			await expect(hint).toContainText(`Club members see you as ${handle}.`);
			await expect(hint.getByRole('link', { name: 'Add your name' })).toHaveAttribute(
				'href',
				'/settings/account',
			);

			await page.getByRole('tab', { name: /^Members/ }).click();
			const memberList = page.locator('.member-list');
			await expect(memberList).toBeVisible({ timeout: 10_000 });
			await expect(memberList.getByText(handle, { exact: true })).toBeVisible();
			await expect(memberList.getByText('Member', { exact: true })).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
