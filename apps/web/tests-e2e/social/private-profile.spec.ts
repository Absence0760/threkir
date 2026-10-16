import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';
import { readCount } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * Private profile and follower approval (decisions § 1967), walked as one
 * journey between two ephemeral users:
 *
 *   1. Owner turns on Private profile in Settings → Privacy (the column lands).
 *   2. Asker opens Owner's profile: the lock panel stands where the runs were,
 *      Owner's public run is not listed, and the button reads Request to follow.
 *   3. Asker requests: the button reads Requested and a follow_requests row
 *      lands — no user_follows edge.
 *   4. Owner opens /follow-requests and approves; the row leaves the list.
 *   5. Asker reloads Owner's profile: Following, and the run is listed.
 *
 * Saga users, so the shared seed's follow graph is never touched; teardown
 * cascades the request, the edge and the run.
 */
test.describe('private profile — request, approve, then see the runs', () => {
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[];
	let owner: SagaUser;
	let asker: SagaUser;

	test.beforeAll(async () => {
		const stamp = Date.now().toString(36);
		users = await createSagaUsers(2, {
			displayNames: [`PrivateSaga Owner ${stamp}`, `PrivateSaga Asker ${stamp}`],
		});
		[owner, asker] = users;
		await insertRun({
			user_id: owner.id,
			started_at: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
			distance_m: 7_000,
			duration_s: 2_100,
			is_public: true,
			metadata: { activity_type: 'run' },
		});
	});

	test.afterAll(async () => {
		if (users) await deleteSagaUsers(users);
	});

	async function contextFor(browser: import('@playwright/test').Browser, user: SagaUser) {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		return ctx;
	}

	test('a stranger asks, the owner approves, and the runs open', async ({ browser }) => {
		const admin = getAdminClient();

		const ownerCtx = await contextFor(browser, owner);
		const ownerPage = await ownerCtx.newPage();
		await ownerPage.goto('/settings/privacy');
		const toggle = ownerPage.getByTestId('private-profile-toggle');
		await expect(toggle).not.toBeChecked();
		await toggle.check();
		await expect
			.poll(async () => {
				const { data } = await admin
					.from('user_profiles')
					.select('profile_private')
					.eq('id', owner.id)
					.maybeSingle();
				return data?.profile_private;
			})
			.toBe(true);

		const askerCtx = await contextFor(browser, asker);
		const askerPage = await askerCtx.newPage();
		await askerPage.goto(`/u/${owner.id}`);
		await expect(askerPage.getByTestId('profile-private-panel')).toBeVisible();
		const follow = askerPage.getByTestId('profile-follow-button');
		await expect(follow).toContainText('Request to follow');

		await follow.click();
		await expect(follow).toContainText('Requested');
		await expect
			.poll(() =>
				readCount(
					'pending request',
					admin
						.from('follow_requests')
						.select('*', { count: 'exact', head: true })
						.eq('requester_id', asker.id)
						.eq('target_id', owner.id)
				)
			)
			.toBe(1);
		expect(
			await readCount(
				'follow edge before approval',
				admin
					.from('user_follows')
					.select('*', { count: 'exact', head: true })
					.eq('follower_id', asker.id)
					.eq('followee_id', owner.id)
			)
		).toBe(0);

		await ownerPage.goto('/follow-requests');
		const list = ownerPage.getByTestId('follow-requests-list');
		await expect(list).toContainText(asker.displayName);
		await list.getByRole('button', { name: `Approve ${asker.displayName}` }).click();
		await expect(ownerPage.getByTestId('follow-requests-empty')).toBeVisible();

		await askerPage.reload();
		await expect(askerPage.getByTestId('profile-follow-button')).toContainText('Following');
		await expect(askerPage.getByTestId('profile-private-panel')).toHaveCount(0);
		await expect(askerPage.locator('.run-card')).toHaveCount(1);

		await askerCtx.close();
		await ownerCtx.close();
	});
});
