import { expect, test } from '../fixtures/test';

import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Creator challenges with a join link (decisions § 2261). A creator copies the
 * invite link off their non-public challenge; a signed-out follower opening it
 * sees the challenge and a sign-up that comes back to the same page; a
 * signed-in one joins in one tap and lands on the challenge. The public share
 * page shows a public challenge and its board without a session.
 *
 * The `challenge_invite_links` gate is open on every local stack (seed.sql).
 * Both users are ephemeral, so the join_challenge_by_token bucket they spend
 * is their own.
 */

let creator: SagaUser;
let joiner: SagaUser;
const privateId = crypto.randomUUID();
const publicId = crypto.randomUUID();

test.describe('challenge invite links', () => {
	test.describe.configure({ mode: 'serial', timeout: 90_000 });

	test.beforeAll(async ({}, testInfo) => {
		[creator, joiner] = await createSagaUsers(2, {
			displayNames: ['Invite Creator', 'Invite Joiner'],
			baseURL: testInfo.project.use.baseURL
		});
		const admin = getAdminClient();
		const now = Date.now();
		const { error } = await admin.from('challenges').insert([
			{
				id: privateId,
				creator_id: creator.id,
				title: 'Invite-only November 50k',
				metric: 'distance',
				scope: 'individual',
				goal_value: 50_000,
				starts_at: new Date(now - 86_400_000).toISOString(),
				ends_at: new Date(now + 29 * 86_400_000).toISOString(),
				is_public: false
			},
			{
				id: publicId,
				creator_id: creator.id,
				title: 'Public December streak',
				metric: 'streak_days',
				scope: 'individual',
				goal_value: 20,
				starts_at: new Date(now - 86_400_000).toISOString(),
				ends_at: new Date(now + 29 * 86_400_000).toISOString(),
				is_public: true
			}
		]);
		if (error) throw error;
		const { error: partErr } = await admin
			.from('challenge_participants')
			.insert({ challenge_id: publicId, user_id: creator.id });
		if (partErr) throw partErr;
	});

	test.afterAll(async () => {
		await getAdminClient().from('challenges').delete().in('id', [privateId, publicId]);
		await deleteSagaUsers([creator, joiner]);
	});

	test('a creator shares the link, a stranger signs up from it, a member joins in one tap', async ({
		browser
	}) => {
		const creatorCtx = await browser.newContext({ storageState: creator.storageStatePath });
		await acceptCookieConsent(creatorCtx);
		const creatorPage = await creatorCtx.newPage();
		await creatorPage.goto(`/challenges/${privateId}`);
		const urlField = creatorPage.getByTestId('challenge-invite-url');
		await expect(urlField).toBeVisible({ timeout: 20_000 });
		const inviteUrl = await urlField.inputValue();
		expect(inviteUrl).toMatch(/\/challenges\/join\/[A-Za-z0-9_-]+$/);
		const invitePath = new URL(inviteUrl).pathname;
		await creatorCtx.close();

		const anonCtx = await browser.newContext();
		await acceptCookieConsent(anonCtx);
		const anonPage = await anonCtx.newPage();
		await anonPage.goto(invitePath);
		const card = anonPage.getByTestId('challenge-join-card');
		await expect(card.getByRole('heading', { name: 'Invite-only November 50k' })).toBeVisible({
			timeout: 20_000
		});
		const signup = card.getByRole('link', { name: 'Create a free account' });
		await expect(signup).toHaveAttribute(
			'href',
			`/login?signup=1&return_to=${encodeURIComponent(invitePath)}`
		);
		await anonCtx.close();

		const joinerCtx = await browser.newContext({ storageState: joiner.storageStatePath });
		await acceptCookieConsent(joinerCtx);
		const joinerPage = await joinerCtx.newPage();
		await joinerPage.goto(invitePath);
		await joinerPage.getByTestId('challenge-join-button').click();
		await expect(joinerPage).toHaveURL(new RegExp(`/challenges/${privateId}$`), { timeout: 20_000 });
		await expect(
			joinerPage.getByRole('heading', { name: 'Invite-only November 50k' })
		).toBeVisible();
		await joinerCtx.close();
	});

	test('a reset link stops working', async ({ browser }) => {
		const creatorCtx = await browser.newContext({ storageState: creator.storageStatePath });
		await acceptCookieConsent(creatorCtx);
		const page = await creatorCtx.newPage();
		await page.goto(`/challenges/${privateId}`);
		const urlField = page.getByTestId('challenge-invite-url');
		await expect(urlField).toBeVisible({ timeout: 20_000 });
		const before = new URL(await urlField.inputValue()).pathname;
		await page.getByTestId('challenge-invite-rotate').click();
		await page.getByRole('dialog').getByRole('button', { name: 'Reset link' }).click();
		await expect(urlField).not.toHaveValue(new RegExp(`${before}$`), { timeout: 15_000 });
		await page.goto(before);
		await expect(page.getByTestId('challenge-join-missing')).toBeVisible({ timeout: 20_000 });
		await creatorCtx.close();
	});

	test('the public share page shows the challenge and its board signed out', async ({ browser }) => {
		const anonCtx = await browser.newContext();
		await acceptCookieConsent(anonCtx);
		const page = await anonCtx.newPage();
		await page.goto(`/share/challenge/${publicId}`);
		const hero = page.getByTestId('share-challenge');
		await expect(hero.getByRole('heading', { name: 'Public December streak' })).toBeVisible({
			timeout: 20_000
		});
		await expect(hero.getByRole('heading', { name: 'Leaderboard' })).toBeVisible();
		await expect(page.getByTestId('share-challenge-signup')).toHaveAttribute(
			'href',
			`/login?signup=1&return_to=${encodeURIComponent(`/share/challenge/${publicId}`)}`
		);
		await page.goto(`/share/challenge/${privateId}`);
		await expect(page.getByRole('heading', { name: 'Challenge not found' })).toBeVisible({
			timeout: 20_000
		});
		await anonCtx.close();
	});
});
