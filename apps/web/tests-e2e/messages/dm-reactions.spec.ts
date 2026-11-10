import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { readRows } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Reactions (issue #1216, migration 20271213121602). A participant picks one
 * of the fixed set under a message, the other side sees it, and tapping the
 * chip again takes it off. A request the viewer has not accepted offers no
 * reaction. pgtap (dm_reactions_test.sql) pins who the server lets react;
 * this pins the page.
 */

async function openAs(browser: Browser, user: SagaUser): Promise<{ page: Page; close: () => Promise<void> }> {
	const ctx = await browser.newContext({ storageState: user.storageStatePath });
	await acceptCookieConsent(ctx);
	const page = await ctx.newPage();
	return { page, close: () => ctx.close() };
}

test.describe('/messages — reactions', () => {
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[] = [];

	test.afterEach(async () => {
		if (users.length > 0) await deleteSagaUsers(users);
		users = [];
	});

	test('a reaction is picked, seen by the other side, and taken off again', async ({ browser }) => {
		const stamp = Date.now().toString(36);
		users = await createSagaUsers(2, { displayNames: [`Reactor ${stamp}`, `Author ${stamp}`] });
		const [reactor, author] = users;
		const admin = getAdminClient();
		const { error: followError } = await admin.from('user_follows').insert({ follower_id: reactor.id, followee_id: author.id });
		if (followError) throw new Error(`follow seed failed: ${followError.message}`);
		const { data: msg, error } = await admin
			.from('direct_messages')
			.insert({ sender_id: author.id, recipient_id: reactor.id, body: `react to me ${stamp}` })
			.select('id')
			.single();
		if (error || !msg) throw new Error(`message seed failed: ${error?.message}`);

		const r = await openAs(browser, reactor);
		try {
			await r.page.goto(`/messages/${author.id}`);
			const bubble = r.page.getByTestId('dm-bubble').filter({ hasText: `react to me ${stamp}` });
			await expect(bubble).toBeVisible({ timeout: 10_000 });
			await bubble.getByTestId('dm-react').click();
			await bubble.locator('[data-testid="dm-reaction-option"][data-reaction="heart"]').click();
			const chip = bubble.locator('[data-testid="dm-reaction-chip"][data-reaction="heart"]');
			await expect(chip).toHaveAttribute('aria-pressed', 'true');
			await expect
				.poll(async () =>
					(await readRows('reactions', admin.from('direct_message_reactions').select('reaction').eq('message_id', msg.id))).map(
						(x) => x.reaction
					)
				)
				.toEqual(['heart']);
		} finally {
			await r.close();
		}

		const a = await openAs(browser, author);
		try {
			await a.page.goto(`/messages/${reactor.id}`);
			const bubble = a.page.getByTestId('dm-bubble').filter({ hasText: `react to me ${stamp}` });
			const chip = bubble.locator('[data-testid="dm-reaction-chip"][data-reaction="heart"]');
			await expect(chip).toBeVisible({ timeout: 10_000 });
			await expect(chip).toHaveAttribute('aria-pressed', 'false');
			await expect(chip).toContainText('1');
		} finally {
			await a.close();
		}

		const again = await openAs(browser, reactor);
		try {
			await again.page.goto(`/messages/${author.id}`);
			const bubble = again.page.getByTestId('dm-bubble').filter({ hasText: `react to me ${stamp}` });
			await bubble.locator('[data-testid="dm-reaction-chip"][data-reaction="heart"]').click();
			await expect(bubble.getByTestId('dm-reaction-chip')).toHaveCount(0);
			await expect
				.poll(async () => (await readRows('reactions', admin.from('direct_message_reactions').select('reaction').eq('message_id', msg.id))).length)
				.toBe(0);
		} finally {
			await again.close();
		}
	});

	test('a pending request offers no reaction to its recipient', async ({ browser }) => {
		const stamp = Date.now().toString(36);
		users = await createSagaUsers(2, { displayNames: [`Asker ${stamp}`, `Askee ${stamp}`] });
		const [asker, askee] = users;
		const admin = getAdminClient();
		const { data: club, error: clubError } = await admin
			.from('clubs')
			.insert({ owner_id: asker.id, name: `React club ${stamp}`, slug: `react-club-${stamp}`, is_public: true })
			.select('id')
			.single();
		if (clubError || !club) throw new Error(`club seed failed: ${clubError?.message}`);
		const { error: memberError } = await admin.from('club_members').upsert(
			[asker, askee].map((u) => ({ club_id: club.id, user_id: u.id, role: u === asker ? 'owner' : 'member', status: 'active' })),
			{ onConflict: 'club_id,user_id' }
		);
		if (memberError) throw new Error(`member seed failed: ${memberError.message}`);

		const s = await openAs(browser, asker);
		try {
			await s.page.goto(`/messages/${askee.id}`);
			await s.page.getByPlaceholder('Message…').fill(`hello ${stamp}`);
			await s.page.getByRole('button', { name: 'Send', exact: true }).click();
			await expect(s.page.getByTestId('dm-bubble').filter({ hasText: `hello ${stamp}` })).toBeVisible({ timeout: 10_000 });
		} finally {
			await s.close();
		}

		const r = await openAs(browser, askee);
		try {
			await r.page.goto(`/messages/${asker.id}`);
			await expect(r.page.getByTestId('dm-request-bar')).toBeVisible({ timeout: 10_000 });
			const bubble = r.page.getByTestId('dm-bubble').filter({ hasText: `hello ${stamp}` });
			await expect(bubble).toBeVisible();
			await expect(bubble.getByTestId('dm-react')).toHaveCount(0);
		} finally {
			await r.close();
		}
	});
});
