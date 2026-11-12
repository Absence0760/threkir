import { expect, test } from '../fixtures/test';

import { browserDayStart } from '../fixtures/dates';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Share-link attribution and Your shares (decisions § 2268). A creator's own
 * share link carries their ref; a signed-out visitor's view of it is counted
 * and the sign-up it offers keeps the ref; a follower who joins through it is
 * attributed to it; the creator reads all of it on /settings/shares.
 *
 * The `share_attribution` gate is open on every local stack (seed.sql). Both
 * users and the challenge are fresh per run, so the counts are exact. An
 * automated browser reports `navigator.webdriver`, which the page counts as a
 * crawler; the signed-out visitor clears it to stand for a person, and the
 * follower keeps it, so one case of each is pinned.
 */

let creator: SagaUser;
let follower: SagaUser;
const challengeId = crypto.randomUUID();
const TITLE = `Attribution 50k ${challengeId.slice(0, 8)}`;

test.describe('share-link attribution', () => {
	test.describe.configure({ mode: 'serial', timeout: 90_000 });

	test.beforeAll(async ({}, testInfo) => {
		[creator, follower] = await createSagaUsers(2, {
			displayNames: ['Share Creator', 'Share Follower'],
			baseURL: testInfo.project.use.baseURL
		});
		const { error } = await getAdminClient().from('challenges').insert({
			id: challengeId,
			creator_id: creator.id,
			title: TITLE,
			metric: 'distance',
			scope: 'individual',
			goal_value: 50_000,
			starts_at: browserDayStart(-1),
			ends_at: browserDayStart(29),
			is_public: true
		});
		if (error) throw error;
	});

	test.afterAll(async () => {
		await getAdminClient().from('challenges').delete().eq('id', challengeId);
		await deleteSagaUsers([creator, follower]);
	});

	test('the creator link carries a ref, and its visit, sign-up offer and join are counted', async ({
		browser
	}) => {
		const creatorCtx = await browser.newContext({ storageState: creator.storageStatePath });
		await acceptCookieConsent(creatorCtx);
		const creatorPage = await creatorCtx.newPage();
		await creatorPage.goto(`/challenges/${challengeId}`);
		const view = creatorPage.getByTestId('challenge-share-view');
		await expect(view).toHaveAttribute(
			'href',
			new RegExp(`/share/challenge/${challengeId}\\?ref=[a-z0-9]{10}$`),
			{ timeout: 20_000 }
		);
		const shared = new URL((await view.getAttribute('href')) ?? '');
		const sharePath = `${shared.pathname}${shared.search}`;

		const anonCtx = await browser.newContext();
		await acceptCookieConsent(anonCtx);
		await anonCtx.addInitScript(() => {
			Object.defineProperty(navigator, 'webdriver', { get: () => false });
		});
		const anonPage = await anonCtx.newPage();
		const visit = anonPage.waitForResponse((r) => r.url().includes('/rest/v1/rpc/record_share_visit'));
		await anonPage.goto(sharePath);
		expect((await visit).ok()).toBe(true);
		await expect(anonPage.getByTestId('share-challenge-signup')).toHaveAttribute(
			'href',
			`/login?signup=1&return_to=${encodeURIComponent(sharePath)}`,
			{ timeout: 20_000 }
		);
		await anonCtx.close();

		const followerCtx = await browser.newContext({ storageState: follower.storageStatePath });
		await acceptCookieConsent(followerCtx);
		const followerPage = await followerCtx.newPage();
		const followerVisit = followerPage.waitForResponse((r) =>
			r.url().includes('/rest/v1/rpc/record_share_visit')
		);
		await followerPage.goto(sharePath);
		await followerVisit;
		const attributed = followerPage.waitForResponse((r) =>
			r.url().includes('/rest/v1/rpc/attribute_share_start')
		);
		await followerPage.getByTestId('share-challenge-join').click();
		expect(await (await attributed).json()).toBe(true);
		await expect(followerPage).toHaveURL(new RegExp(`/challenges/${challengeId}$`), {
			timeout: 20_000
		});
		await followerCtx.close();

		await creatorPage.goto('/settings/shares');
		await expect(creatorPage.getByRole('link', { name: 'Your shares' })).toBeVisible({
			timeout: 20_000
		});
		const row = creatorPage.getByTestId('share-row').filter({ hasText: TITLE });
		await expect(row.getByTestId('share-visits')).toHaveText('1', { timeout: 20_000 });
		await expect(row.getByTestId('share-joins')).toHaveText('1');
		await expect(row.getByText('1 through your link')).toHaveCount(2);
		await expect(row).toContainText('Plus 1 visit from a crawler, not counted above.');
		await creatorCtx.close();
	});

	test('a failed load says so and offers a retry', async ({ browser, mockRoute }) => {
		const ctx = await browser.newContext({ storageState: creator.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		await mockRoute(page, '**/rest/v1/rpc/my_share_stats**', (route) =>
			route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' })
		);
		await page.goto('/settings/shares');
		await expect(page.getByRole('alert')).toContainText("Couldn't load your shares.", {
			timeout: 20_000
		});
		await expect(page.getByRole('button', { name: 'Try again' })).toBeVisible();
		await ctx.close();
	});
});
