import type { Browser } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { readMaybeRow, readRows } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Message requests (issue #1216, decisions § 2384).
 *
 * Two club members who do not follow each other can message first, and the
 * message lands in the recipient's Requests list rather than the inbox. The
 * recipient accepts, declines (confirmed) or blocks (confirmed); the
 * requester may send three messages until then, and a stranger with no shared
 * club or event is refused. pgtap (dm_message_requests_test.sql) pins the
 * server rules; this pins what each side sees.
 *
 * Every user is an ephemeral saga user: requests spend the requester's own
 * open_message_request bucket, and decline and block change the pair's state.
 */

test.describe('/messages — message requests', () => {
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[] = [];
	let requester: SagaUser;
	let recipient: SagaUser;
	let decliner: SagaUser;
	let blocker: SagaUser;
	let stranger: SagaUser;
	let clubId: string;

	test.beforeAll(async () => {
		const stamp = Date.now().toString(36);
		users = await createSagaUsers(5, {
			displayNames: [
				`Requester ${stamp}`,
				`Recipient ${stamp}`,
				`Decliner ${stamp}`,
				`Blocker ${stamp}`,
				`Stranger ${stamp}`
			]
		});
		[requester, recipient, decliner, blocker, stranger] = users;
		const admin = getAdminClient();
		const { data: club, error: clubError } = await admin
			.from('clubs')
			.insert({ owner_id: requester.id, name: `Requests ${stamp}`, slug: `requests-${stamp}`, is_public: true })
			.select('id')
			.single();
		if (clubError || !club) throw new Error(`club seed failed: ${clubError?.message}`);
		clubId = club.id;
		const { error: memberError } = await admin.from('club_members').upsert(
			[requester, recipient, decliner, blocker].map((u) => ({
				club_id: clubId,
				user_id: u.id,
				role: u === requester ? 'owner' : 'member',
				status: 'active'
			})),
			{ onConflict: 'club_id,user_id' }
		);
		if (memberError) throw new Error(`membership seed failed: ${memberError.message}`);
	});

	test.afterAll(async () => {
		if (clubId) await getAdminClient().from('clubs').delete().eq('id', clubId);
		if (users.length > 0) await deleteSagaUsers(users);
	});

	async function open(browser: Browser, user: SagaUser) {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		return { ctx, page: await ctx.newPage() };
	}

	// A request the recipient's side has not answered, seeded the way the
	// requester's own send leaves it: the service-role insert runs the same
	// trigger, so the recipient's participant row is pending.
	async function seedRequest(from: SagaUser, to: SagaUser, body: string) {
		const { error } = await getAdminClient()
			.from('direct_messages')
			.insert({ sender_id: from.id, recipient_id: to.id, body });
		if (error) throw new Error(`request seed failed: ${error.message}`);
	}

	async function requestState(of: SagaUser, partner: SagaUser) {
		const admin = getAdminClient();
		const msgs = await readRows(
			'the pair\'s messages',
			admin
				.from('direct_messages')
				.select('conversation_id')
				.in('sender_id', [of.id, partner.id])
				.in('recipient_id', [of.id, partner.id])
				.limit(1)
		);
		if (msgs.length === 0) return undefined;
		const row = await readMaybeRow(
			'the participant row',
			admin
				.from('conversation_participants')
				.select('request_state')
				.eq('conversation_id', msgs[0].conversation_id)
				.eq('user_id', of.id)
				.maybeSingle()
		);
		return row?.request_state ?? null;
	}

	test('a club member messages first, is capped at three, and the recipient accepts from Requests', async ({
		browser
	}) => {
		const a = await open(browser, requester);
		try {
			await a.page.goto(`/messages/${recipient.id}`);
			const composer = a.page.getByPlaceholder('Message…');
			await expect(composer).toBeVisible({ timeout: 10_000 });
			for (const text of ['hello from the club', 'second', 'third']) {
				await composer.fill(text);
				await a.page.getByRole('button', { name: 'Send', exact: true }).click();
				await expect(a.page.getByTestId('dm-bubble').filter({ hasText: text })).toBeVisible({ timeout: 10_000 });
			}
			await composer.fill('fourth');
			await a.page.getByRole('button', { name: 'Send', exact: true }).click();
			await expect(a.page.getByText('You can send up to 3 messages until they accept your request.')).toBeVisible({
				timeout: 10_000
			});
		} finally {
			await a.ctx.close();
		}
		expect(await requestState(recipient, requester)).toBe('pending');

		const b = await open(browser, recipient);
		try {
			await b.page.goto('/messages');
			const toggle = b.page.getByTestId('inbox-show-requests');
			await expect(toggle).toContainText('Requests (1)', { timeout: 10_000 });
			// The request is not in the inbox itself.
			await expect(b.page.locator('a.thread', { hasText: requester.displayName })).toHaveCount(0);
			await toggle.click();
			await b.page.locator('a.thread', { hasText: requester.displayName }).click();

			const bar = b.page.getByTestId('dm-request-bar');
			await expect(bar).toContainText(`${requester.displayName} wants to message you.`, { timeout: 10_000 });
			await expect(b.page.getByPlaceholder('Message…')).toHaveCount(0);
			await expect(b.page.getByTestId('dm-bubble')).toHaveCount(3);

			await b.page.getByTestId('dm-request-accept').click();
			await expect(bar).toHaveCount(0, { timeout: 10_000 });
			await expect(b.page.getByPlaceholder('Message…')).toBeVisible();
			await expect.poll(() => requestState(recipient, requester), { timeout: 10_000 }).toBe('accepted');
			// With no request left, the list falls back to the inbox, which now has it.
			await expect(b.page.getByTestId('inbox-show-requests')).toHaveCount(0);
			await expect(b.page.locator('a.thread', { hasText: requester.displayName })).toBeVisible();
		} finally {
			await b.ctx.close();
		}
	});

	test('Decline is confirmed, and the request leaves every list', async ({ browser }) => {
		await seedRequest(decliner, recipient, 'please decline me');
		const b = await open(browser, recipient);
		try {
			await b.page.goto(`/messages/${decliner.id}`);
			await expect(b.page.getByTestId('dm-request-bar')).toBeVisible({ timeout: 10_000 });

			await b.page.getByTestId('dm-request-decline').click();
			const dialog = b.page.getByTestId('dm-request-decline-confirm');
			await expect(dialog).toContainText('Decline this request?');
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			expect(await requestState(recipient, decliner)).toBe('pending');

			await b.page.getByTestId('dm-request-decline').click();
			await dialog.getByRole('button', { name: 'Decline', exact: true }).click();
			await expect(b.page).toHaveURL(/\/messages$/, { timeout: 10_000 });
			await expect.poll(() => requestState(recipient, decliner), { timeout: 10_000 }).toBe('declined');
			await expect(b.page.locator('a.thread', { hasText: decliner.displayName })).toHaveCount(0);
			await expect(b.page.getByTestId('inbox-show-requests')).toHaveCount(0);
		} finally {
			await b.ctx.close();
		}

		// The requester is refused with the same sentence a block or a missing
		// follow edge answers.
		const d = await open(browser, decliner);
		try {
			await d.page.goto(`/messages/${recipient.id}`);
			const composer = d.page.getByPlaceholder('Message…');
			await expect(composer).toBeVisible({ timeout: 10_000 });
			await composer.fill('one more');
			await d.page.getByRole('button', { name: 'Send', exact: true }).click();
			await expect(d.page.getByText(/unless either of you has blocked the other/)).toBeVisible({ timeout: 10_000 });
		} finally {
			await d.ctx.close();
		}
	});

	test('Block from a request is confirmed and files the block', async ({ browser }) => {
		await seedRequest(blocker, recipient, 'please block me');
		const b = await open(browser, recipient);
		try {
			await b.page.goto(`/messages/${blocker.id}`);
			await expect(b.page.getByTestId('dm-request-bar')).toBeVisible({ timeout: 10_000 });
			await b.page.getByTestId('dm-request-block').click();
			const dialog = b.page.getByTestId('dm-block-confirm');
			await expect(dialog).toContainText(`Block ${blocker.displayName}?`);
			await dialog.getByRole('button', { name: 'Block', exact: true }).click();
			await expect(b.page).toHaveURL(/\/messages$/, { timeout: 10_000 });
			await expect
				.poll(
					() =>
						readMaybeRow(
							'the block',
							getAdminClient()
								.from('user_blocks')
								.select('blocker_id')
								.eq('blocker_id', recipient.id)
								.eq('blocked_id', blocker.id)
								.maybeSingle()
						),
					{ timeout: 10_000 }
				)
				.not.toBeNull();
			expect(await requestState(recipient, blocker)).toBe('declined');
		} finally {
			await b.ctx.close();
		}
	});

	test('a stranger with no shared club or event is refused', async ({ browser }) => {
		const s = await open(browser, stranger);
		try {
			await s.page.goto(`/messages/${recipient.id}`);
			const composer = s.page.getByPlaceholder('Message…');
			await expect(composer).toBeVisible({ timeout: 10_000 });
			await composer.fill('cold message');
			await s.page.getByRole('button', { name: 'Send', exact: true }).click();
			await expect(
				s.page.getByText(
					'You can message people you follow or who follow you, or someone you share a club or an event with, unless either of you has blocked the other.'
				)
			).toBeVisible({ timeout: 10_000 });
			const sent = await readRows(
				'the stranger\'s messages',
				getAdminClient().from('direct_messages').select('id').eq('sender_id', stranger.id)
			);
			expect(sent).toHaveLength(0);
		} finally {
			await s.ctx.close();
		}
	});
});
