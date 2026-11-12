import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { readRows } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Group conversations on web (issue #1365 slice 2, decisions § 2463).
 *
 * One group walked from creation to removal, as each person sees it: the owner
 * creates it and invites two people, who join from Requests; a member's
 * message carries their name; a late joiner reads nothing from before they
 * joined; a member who blocked someone sees a placeholder in place of that
 * person's message while everyone else sees the message; a removed member and
 * a stranger who knows the URL both meet "not available"; a leaver keeps only
 * their own messages; an invitee can report the invite before accepting it.
 * pgtap (group_messages_*_test.sql) pins the server rules; this pins what each
 * side is shown.
 *
 * Every user is an ephemeral saga user: the group RPCs spend each caller's
 * own create_group_conversation and invite_to_group buckets, and blocks,
 * removals and leaves change state no other spec should inherit. The serial
 * steps share one group.
 */

test.describe.configure({ mode: 'serial', timeout: 90_000 });

test.describe('/messages — group conversations', () => {
	const stamp = Date.now().toString(36);
	const title = `Tempo crew ${stamp}`;
	let users: SagaUser[] = [];
	let owner: SagaUser;
	let bea: SagaUser;
	let cal: SagaUser;
	let dev: SagaUser;
	let stranger: SagaUser;
	let groupId = '';

	test.beforeAll(async () => {
		users = await createSagaUsers(5, {
			displayNames: [`Owner ${stamp}`, `Bea ${stamp}`, `Cal ${stamp}`, `Dev ${stamp}`, `Stranger ${stamp}`],
		});
		[owner, bea, cal, dev, stranger] = users;
		const { error } = await getAdminClient()
			.from('user_follows')
			.insert([bea, cal, dev].map((u) => ({ follower_id: owner.id, followee_id: u.id })));
		if (error) throw new Error(`follow seed failed: ${error.message}`);
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (groupId) {
			await admin.from('reports').delete().eq('target_kind', 'group_invite').eq('target_id', groupId);
			await admin.from('direct_messages').delete().eq('conversation_id', groupId);
			await admin.from('conversations').delete().eq('id', groupId);
		}
		if (users.length > 0) await deleteSagaUsers(users);
	});

	async function open(browser: Browser, user: SagaUser) {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		return { ctx, page: await ctx.newPage() };
	}

	async function send(page: Page, text: string) {
		await page.getByPlaceholder('Message…').fill(text);
		await page.getByRole('button', { name: 'Send', exact: true }).click();
		await expect(page.getByTestId('dm-bubble').filter({ hasText: text })).toBeVisible({ timeout: 10_000 });
	}

	async function acceptFromRequests(page: Page) {
		await page.goto('/messages');
		const toggle = page.getByTestId('inbox-show-requests');
		await expect(toggle).toBeVisible({ timeout: 15_000 });
		await toggle.click();
		const invite = page.getByTestId('inbox-group-invite').filter({ hasText: title });
		await expect(invite).toContainText(`${owner.displayName} invited you`);
		await invite.getByTestId('group-invite-accept').click();
		await expect(page).toHaveURL(new RegExp(`/messages/group/${groupId}$`), { timeout: 15_000 });
		await expect(page.getByTestId('group-title')).toHaveText(title);
	}

	test('the owner creates a group and the invitees join from Requests', async ({ browser }) => {
		const a = await open(browser, owner);
		try {
			await a.page.goto('/messages');
			await a.page.getByTestId('inbox-new-group').click();
			const dialog = a.page.getByTestId('group-create-dialog');
			await dialog.getByTestId('group-title-input').fill(`  ${title}  `);
			await dialog.locator(`[data-testid="group-person"][data-user-id="${bea.id}"]`).check();
			await dialog.locator(`[data-testid="group-person"][data-user-id="${cal.id}"]`).check();
			await expect(dialog.getByTestId('group-people-count')).toContainText('2 of 31');
			await dialog.getByTestId('group-create-submit').click();
			await expect(a.page).toHaveURL(/\/messages\/group\/[0-9a-f-]{36}$/, { timeout: 15_000 });
			groupId = a.page.url().split('/').pop() ?? '';
			await expect(a.page.getByTestId('group-title')).toHaveText(title);
		} finally {
			await a.ctx.close();
		}

		const invites = await readRows(
			'the two invites',
			getAdminClient()
				.from('conversation_participants')
				.select('user_id, membership_state')
				.eq('conversation_id', groupId)
				.eq('membership_state', 'invited'),
		);
		expect(invites.map((r) => r.user_id).sort()).toEqual([bea.id, cal.id].sort());

		for (const invitee of [bea, cal]) {
			const s = await open(browser, invitee);
			try {
				await acceptFromRequests(s.page);
			} finally {
				await s.ctx.close();
			}
		}
	});

	test('a member sends, and the others see it under their name', async ({ browser }) => {
		const b = await open(browser, bea);
		try {
			await b.page.goto(`/messages/group/${groupId}`);
			await send(b.page, `hello group ${stamp}`);
		} finally {
			await b.ctx.close();
		}
		const a = await open(browser, owner);
		try {
			await a.page.goto(`/messages/group/${groupId}`);
			const bubble = a.page.getByTestId('dm-bubble').filter({ hasText: `hello group ${stamp}` });
			await expect(bubble).toBeVisible({ timeout: 15_000 });
			await expect(bubble.getByTestId('group-sender')).toHaveText(bea.displayName);
			await a.page.goto('/messages');
			const row = a.page.getByTestId('inbox-group-row').filter({ hasText: title });
			await expect(row.getByTestId('inbox-group-members')).toHaveText('3 members');
		} finally {
			await a.ctx.close();
		}
	});

	test('text typed while a send is in flight stays in the composer', async ({ browser }) => {
		const b = await open(browser, bea);
		try {
			await b.page.goto(`/messages/group/${groupId}`);
			await expect(b.page.getByTestId('dm-bubble').filter({ hasText: `hello group ${stamp}` })).toBeVisible({
				timeout: 15_000,
			});
			let release!: () => void;
			const held = new Promise<void>((r) => (release = r));
			await b.page.route('**/rest/v1/direct_messages*', async (route) => {
				if (route.request().method() === 'POST') await held;
				await route.continue();
			});
			const composer = b.page.getByPlaceholder('Message…');
			await composer.fill(`slow one ${stamp}`);
			await b.page.getByRole('button', { name: 'Send', exact: true }).click();
			await composer.fill(`typed meanwhile ${stamp}`);
			release();
			await expect(b.page.getByTestId('dm-bubble').filter({ hasText: `slow one ${stamp}` })).toBeVisible({
				timeout: 10_000,
			});
			await expect(composer).toHaveValue(`typed meanwhile ${stamp}`);
		} finally {
			await b.ctx.close();
		}
	});

	test('a failed flag read is not "off": the next poll reads it again and the group appears', async ({ browser }) => {
		const a = await open(browser, owner);
		try {
			await a.page.route('**/rest/v1/rpc/group_messages_enabled*', (route) =>
				route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"blip"}' }),
			);
			await a.page.goto(`/messages/group/${groupId}`);
			await expect(a.page.getByRole('heading', { name: 'Messages', level: 2 })).toBeVisible({ timeout: 15_000 });
			// Unknown renders as nothing of the group, and not as "not available".
			await expect(a.page.getByTestId('inbox-new-group')).toHaveCount(0);
			await expect(a.page.getByTestId('dm-bubble')).toHaveCount(0);
			await expect(a.page.getByTestId('group-unavailable')).toHaveCount(0);

			await a.page.unroute('**/rest/v1/rpc/group_messages_enabled*');
			// The thread's 10 s poll and the inbox's 30 s poll each read the flag again.
			await expect(a.page.getByTestId('dm-bubble').filter({ hasText: `hello group ${stamp}` })).toBeVisible({
				timeout: 20_000,
			});
			await expect(a.page.getByTestId('inbox-new-group')).toBeVisible({ timeout: 40_000 });
			await expect(a.page.getByTestId('inbox-group-row').filter({ hasText: title })).toBeVisible();
		} finally {
			await a.ctx.close();
		}
	});

	test('a late joiner reads nothing from before they joined', async ({ browser }) => {
		const a = await open(browser, owner);
		try {
			await a.page.goto(`/messages/group/${groupId}`);
			await send(a.page, `before dev ${stamp}`);
			await a.page.getByTestId('group-members-button').click();
			const sheet = a.page.getByTestId('group-members-sheet');
			await sheet.getByTestId('group-invite-more').click();
			await sheet.locator(`[data-testid="group-person"][data-user-id="${dev.id}"]`).check();
			await sheet.getByTestId('group-invite-send').click();
			await expect(sheet.locator(`[data-testid="group-member"][data-user-id="${dev.id}"]`)).toHaveAttribute(
				'data-role',
				'invited',
				{ timeout: 10_000 },
			);
		} finally {
			await a.ctx.close();
		}

		const d = await open(browser, dev);
		try {
			// The invite can be reported before it is accepted; the report keeps
			// the title and the inviter Dev was shown (20271224000800).
			await d.page.goto('/messages');
			await d.page.getByTestId('inbox-show-requests').click({ timeout: 15_000 });
			const invite = d.page.getByTestId('inbox-group-invite').filter({ hasText: title });
			await invite.getByTestId('group-invite-report').click();
			const dialog = d.page.getByRole('dialog', { name: 'Report this group invitation' });
			await expect(dialog).toBeVisible();
			await dialog.getByRole('radio', { name: /Spam/ }).check();
			await dialog.getByRole('button', { name: 'Submit report' }).click();
			await expect(d.page.getByText('Report submitted. Thanks for flagging.')).toBeVisible({ timeout: 10_000 });
			const reports = await readRows(
				'the invite report',
				getAdminClient()
					.from('reports')
					.select('reason, snapshot_body, snapshot_author_id')
					.eq('target_kind', 'group_invite')
					.eq('target_id', groupId)
					.eq('reporter_id', dev.id),
			);
			expect(reports).toEqual([{ reason: 'spam', snapshot_body: title, snapshot_author_id: owner.id }]);

			await acceptFromRequests(d.page);
			await expect(d.page.getByTestId('group-history-note')).toBeVisible();
			await send(d.page, `dev says hi ${stamp}`);
			await expect(d.page.getByTestId('dm-bubble').filter({ hasText: `before dev ${stamp}` })).toHaveCount(0);
			await expect(d.page.getByTestId('dm-bubble').filter({ hasText: `hello group ${stamp}` })).toHaveCount(0);
		} finally {
			await d.ctx.close();
		}
	});

	test('a member who blocked someone sees a placeholder where their message was', async ({ browser }) => {
		const admin = getAdminClient();
		const { error: blockError } = await admin.from('user_blocks').insert({ blocker_id: cal.id, blocked_id: bea.id });
		if (blockError) throw new Error(`block seed failed: ${blockError.message}`);
		const b = await open(browser, bea);
		try {
			await b.page.goto(`/messages/group/${groupId}`);
			await send(b.page, `can cal read this ${stamp}`);
		} finally {
			await b.ctx.close();
		}

		const c = await open(browser, cal);
		try {
			await c.page.goto(`/messages/group/${groupId}`);
			await expect(c.page.getByTestId('dm-bubble').filter({ hasText: `dev says hi ${stamp}` })).toBeVisible({
				timeout: 15_000,
			});
			// Bea's three messages: hello group, the slow send, and this one.
			await expect(c.page.getByTestId('group-blocked-placeholder')).toHaveCount(3);
			await expect(c.page.getByText(`can cal read this ${stamp}`)).toHaveCount(0);
			await expect(c.page.getByText(`hello group ${stamp}`)).toHaveCount(0);
		} finally {
			await c.ctx.close();
		}

		const a = await open(browser, owner);
		try {
			await a.page.goto(`/messages/group/${groupId}`);
			await expect(a.page.getByTestId('dm-bubble').filter({ hasText: `can cal read this ${stamp}` })).toBeVisible({
				timeout: 15_000,
			});
			await expect(a.page.getByTestId('group-blocked-placeholder')).toHaveCount(0);
		} finally {
			await a.ctx.close();
		}
	});

	test('the owner removes a member, behind a confirm, and the open thread loses the group without a reload', async ({
		browser
	}) => {
		const c = await open(browser, cal);
		const a = await open(browser, owner);
		try {
			// Cal has the group open, and keeps it open through the removal.
			await c.page.goto(`/messages/group/${groupId}`);
			await expect(c.page.getByTestId('dm-bubble').filter({ hasText: `dev says hi ${stamp}` })).toBeVisible({
				timeout: 15_000,
			});

			await a.page.goto(`/messages/group/${groupId}`);
			await a.page.getByTestId('group-members-button').click();
			const sheet = a.page.getByTestId('group-members-sheet');
			await sheet
				.locator(`[data-testid="group-member"][data-user-id="${cal.id}"]`)
				.getByTestId('group-member-remove')
				.click();
			const confirm = a.page.getByTestId('group-remove-confirm');
			await expect(confirm).toContainText(`Remove ${cal.displayName} from the group?`);
			await confirm.getByRole('button', { name: 'Remove', exact: true }).click();
			await expect(sheet.locator(`[data-testid="group-member"][data-user-id="${cal.id}"]`)).toHaveCount(0, {
				timeout: 10_000,
			});
			await expect(sheet.locator(`[data-testid="group-member"][data-user-id="${bea.id}"]`)).toBeVisible();

			// The next 10 s poll takes the group away from the open page.
			await expect(c.page.getByTestId('group-unavailable')).toBeVisible({ timeout: 25_000 });
			await expect(c.page.getByText(`dev says hi ${stamp}`)).toHaveCount(0);

			await c.page.reload();
			await expect(c.page.getByTestId('group-unavailable')).toBeVisible({ timeout: 15_000 });
			await expect(c.page.getByText(title)).toHaveCount(0);
		} finally {
			await a.ctx.close();
			await c.ctx.close();
		}
	});

	test('someone outside the group is refused at the URL', async ({ browser }) => {
		const s = await open(browser, stranger);
		try {
			await s.page.goto(`/messages/group/${groupId}`);
			await expect(s.page.getByTestId('group-unavailable')).toBeVisible({ timeout: 15_000 });
			await expect(s.page.getByText(title)).toHaveCount(0);
			await expect(s.page.getByTestId('dm-bubble')).toHaveCount(0);
		} finally {
			await s.ctx.close();
		}
	});

	test('a member leaves, behind a confirm, and keeps only their own messages', async ({ browser }) => {
		const b = await open(browser, bea);
		try {
			await b.page.goto(`/messages/group/${groupId}`);
			await expect(b.page.getByTestId('dm-bubble').filter({ hasText: `before dev ${stamp}` })).toBeVisible({
				timeout: 15_000,
			});
			await b.page.getByTestId('group-leave').click();
			await b.page
				.getByTestId('group-leave-confirm')
				.getByRole('button', { name: 'Leave', exact: true })
				.click();
			await expect(b.page).toHaveURL(/\/messages$/, { timeout: 15_000 });
			const row = b.page.getByTestId('inbox-group-row').filter({ hasText: title });
			await expect(row.getByTestId('inbox-group-left')).toHaveText('You left this group', { timeout: 15_000 });

			await row.click();
			await expect(b.page.getByTestId('group-left-notice')).toBeVisible({ timeout: 15_000 });
			await expect(b.page.getByTestId('dm-bubble').filter({ hasText: `hello group ${stamp}` })).toBeVisible();
			await expect(b.page.getByTestId('dm-bubble').filter({ hasText: `before dev ${stamp}` })).toHaveCount(0);
			await expect(b.page.getByPlaceholder('Message…')).toHaveCount(0);
		} finally {
			await b.ctx.close();
		}
	});

	test('with group conversations off, nothing of them is shown', async ({ browser }) => {
		const a = await open(browser, owner);
		try {
			// The surface reads group_messages_enabled() and fails closed; the
			// flag itself is server state no spec should flip for the whole run.
			await a.page.route('**/rest/v1/rpc/group_messages_enabled*', (route) =>
				route.fulfill({ status: 200, contentType: 'application/json', body: 'false' }),
			);
			await a.page.goto('/messages');
			await expect(a.page.getByRole('heading', { name: 'Messages', level: 2 })).toBeVisible({ timeout: 15_000 });
			await expect(a.page.getByTestId('inbox-new-group')).toHaveCount(0);
			await expect(a.page.getByTestId('inbox-group-row')).toHaveCount(0);

			await a.page.goto(`/messages/group/${groupId}`);
			await expect(a.page.getByTestId('group-unavailable')).toBeVisible({ timeout: 15_000 });
			await expect(a.page.getByTestId('dm-bubble')).toHaveCount(0);

			// A failed read shows nothing of them either.
			await a.page.unroute('**/rest/v1/rpc/group_messages_enabled*');
			await a.page.route('**/rest/v1/rpc/group_messages_enabled*', (route) =>
				route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' }),
			);
			await a.page.goto('/messages');
			await expect(a.page.getByRole('heading', { name: 'Messages', level: 2 })).toBeVisible({ timeout: 15_000 });
			await expect(a.page.getByTestId('inbox-new-group')).toHaveCount(0);
		} finally {
			await a.ctx.close();
		}
	});
});
