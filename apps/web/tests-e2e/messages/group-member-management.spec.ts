import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { readRow, readRows } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * A group's member sheet and people picker on web (issue #1365 slice 2,
 * group_messages.md § 2): what the owner, an admin and a plain member are each
 * offered, and what the server keeps when they use it. Roles change and come
 * back, ownership is handed on only through its confirm, a rename writes its
 * line into the thread and a title the server would refuse is refused with
 * its message, an invitation from the follow graph lands, and the picker's
 * search and its 32-seat cap, which counts live invitations, hold.
 *
 * group-conversations.spec.ts walks a group's life from creation to removal;
 * this one starts from a group seeded through the RPCs as its own users (the
 * creation flow is that spec's) and drives every change through the sheet.
 * The seat-filling followees are admin-created without a session: nobody
 * signs in as them, they only take seats. Every user is ephemeral, because
 * the group RPCs spend each caller's own rate-limit buckets.
 */

test.describe.configure({ mode: 'serial', timeout: 90_000 });

const FILLERS = 30;

test.describe('/messages — group members sheet and people picker', () => {
	const stamp = Date.now().toString(36);
	const title = `Long run club ${stamp}`;
	let users: SagaUser[] = [];
	let owner: SagaUser;
	let ann: SagaUser;
	let ben: SagaUser;
	let cid: SagaUser;
	let fillers: SagaUser[] = [];
	let groupId = '';

	const fillerName = (i: number) => `Pacer ${stamp} ${String(i).padStart(2, '0')}`;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		users = await createSagaUsers(4, {
			displayNames: [`Owner ${stamp}`, `Ann ${stamp}`, `Ben ${stamp}`, `Cid ${stamp}`],
		});
		[owner, ann, ben, cid] = users;

		fillers = await Promise.all(
			Array.from({ length: FILLERS }, async (_, i) => {
				const email = `group-filler-${stamp}-${i}@test.com`;
				const { data, error } = await admin.auth.admin.createUser({
					email,
					password: 'sagatest123',
					email_confirm: true,
				});
				if (error || !data?.user) throw new Error(`filler #${i} failed: ${error?.message}`);
				const { error: profileError } = await admin
					.from('user_profiles')
					.upsert({ id: data.user.id, display_name: fillerName(i), preferred_unit: 'km' });
				if (profileError) throw new Error(`filler #${i} profile failed: ${profileError.message}`);
				return { id: data.user.id, email, password: 'sagatest123', displayName: fillerName(i), storageStatePath: '' };
			}),
		);

		const { error: followError } = await admin
			.from('user_follows')
			.insert([ann, ben, cid, ...fillers].map((u) => ({ follower_id: owner.id, followee_id: u.id })));
		if (followError) throw new Error(`follow seed failed: ${followError.message}`);

		// Four members and five live invitations: 23 of the 32 seats left.
		const ownerClient = await getUserClient(owner);
		const { data: id, error: createError } = await ownerClient.rpc('create_group_conversation', {
			p_title: title,
			p_invitees: [ann, ben, cid, ...fillers.slice(0, 5)].map((u) => u.id),
		});
		if (createError || typeof id !== 'string') throw new Error(`group seed failed: ${createError?.message}`);
		groupId = id;
		for (const member of [ann, ben, cid]) {
			const client = await getUserClient(member);
			const { error } = await client.rpc('accept_group_invite', { p_conversation_id: groupId });
			if (error) throw new Error(`accept seed failed: ${error.message}`);
		}
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (groupId) {
			await admin.from('direct_messages').delete().eq('conversation_id', groupId);
			await admin.from('conversations').delete().eq('id', groupId);
		}
		if (users.length > 0) await deleteSagaUsers(users);
		if (fillers.length > 0) await deleteSagaUsers(fillers);
	});

	async function openAs(browser: Browser, user: SagaUser) {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		return { ctx, page: await ctx.newPage() };
	}

	async function openSheet(page: Page) {
		await page.goto(`/messages/group/${groupId}`);
		await expect(page.getByTestId('group-title')).toBeVisible({ timeout: 15_000 });
		await page.getByTestId('group-members-button').click();
		const sheet = page.getByTestId('group-members-sheet');
		await expect(sheet.getByTestId('group-member').first()).toBeVisible({ timeout: 10_000 });
		return sheet;
	}

	function memberRow(page: Page, user: SagaUser) {
		return page.getByTestId('group-members-sheet').locator(`[data-testid="group-member"][data-user-id="${user.id}"]`);
	}

	async function roles(): Promise<Map<string, string | null>> {
		const rows = await readRows(
			'the group roster',
			getAdminClient()
				.from('conversation_participants')
				.select('user_id, role, membership_state')
				.eq('conversation_id', groupId)
				.in('membership_state', ['active', 'invited']),
		);
		return new Map(rows.map((r) => [r.user_id as string, r.role as string | null]));
	}

	test('a plain member is offered no role, removal, rename or invite controls', async ({ browser }) => {
		const a = await openAs(browser, ann);
		try {
			const sheet = await openSheet(a.page);
			await expect(memberRow(a.page, owner)).toHaveAttribute('data-role', 'owner');
			await expect(memberRow(a.page, ben)).toBeVisible();
			for (const id of [
				'group-member-promote',
				'group-member-demote',
				'group-member-transfer',
				'group-member-remove',
				'group-rename',
				'group-invite-more',
			]) {
				await expect(sheet.getByTestId(id)).toHaveCount(0);
			}
		} finally {
			await a.ctx.close();
		}
	});

	test('the owner makes a member an admin and takes it back', async ({ browser }) => {
		const o = await openAs(browser, owner);
		try {
			await openSheet(o.page);
			await memberRow(o.page, ann).getByTestId('group-member-promote').click();
			await expect(memberRow(o.page, ann)).toHaveAttribute('data-role', 'admin', { timeout: 10_000 });
			await expect(memberRow(o.page, ann).getByTestId('group-member-demote')).toBeVisible();
			expect((await roles()).get(ann.id)).toBe('admin');

			// An admin manages the group but is not offered the owner's role controls.
			const a = await openAs(browser, ann);
			try {
				const sheet = await openSheet(a.page);
				await expect(sheet.getByTestId('group-rename')).toBeVisible();
				await expect(sheet.getByTestId('group-invite-more')).toBeVisible();
				await expect(sheet.getByTestId('group-member-promote')).toHaveCount(0);
				await expect(sheet.getByTestId('group-member-demote')).toHaveCount(0);
				await expect(sheet.getByTestId('group-member-transfer')).toHaveCount(0);
				await expect(memberRow(a.page, owner).getByTestId('group-member-remove')).toHaveCount(0);
				await expect(memberRow(a.page, ben).getByTestId('group-member-remove')).toBeVisible();
			} finally {
				await a.ctx.close();
			}

			await memberRow(o.page, ann).getByTestId('group-member-demote').click();
			await expect(memberRow(o.page, ann)).toHaveAttribute('data-role', 'member', { timeout: 10_000 });
			expect((await roles()).get(ann.id)).toBe('member');
			await o.page.reload();
			await openSheet(o.page);
			await expect(memberRow(o.page, ann)).toHaveAttribute('data-role', 'member');
			await expect(memberRow(o.page, ann).getByTestId('group-member-promote')).toBeVisible();
		} finally {
			await o.ctx.close();
		}
	});

	test('a rename writes its line, and a title the server refuses is refused with its message', async ({
		browser,
	}) => {
		// 60 characters with emoji in them: 60 code points, far more UTF-16
		// units, which an input's maxlength would have cut short.
		const head = `Hill reps ${stamp} `;
		const renamed = head + '🏃'.repeat(60 - Array.from(head).length);
		expect(Array.from(renamed)).toHaveLength(60);

		const o = await openAs(browser, owner);
		try {
			const sheet = await openSheet(o.page);
			await sheet.getByTestId('group-rename').click();
			const input = sheet.getByTestId('group-rename-input');
			await expect(input).toHaveValue(title);
			await expect(sheet.getByTestId('group-rename-error')).toHaveCount(0);

			await input.fill('   ');
			await expect(sheet.getByTestId('group-rename-error')).toHaveText('A group name is 1 to 60 characters.');
			await expect(sheet.getByTestId('group-rename-save')).toBeDisabled();

			await input.fill(`${renamed}🏃`);
			await expect(input).toHaveValue(`${renamed}🏃`);
			await expect(sheet.getByTestId('group-rename-error')).toHaveText('A group name is 1 to 60 characters.');
			await expect(sheet.getByTestId('group-rename-save')).toBeDisabled();

			await input.fill(renamed);
			await expect(input).toHaveValue(renamed);
			await expect(sheet.getByTestId('group-rename-error')).toHaveCount(0);
			await sheet.getByTestId('group-rename-save').click();
			await expect(sheet.getByTestId('group-rename-input')).toHaveCount(0, { timeout: 10_000 });
			await expect(o.page.getByTestId('group-title')).toHaveText(renamed);
			await o.page.keyboard.press('Escape');
			await expect(
				o.page.getByTestId('group-renamed-line').filter({ hasText: `You renamed the group to ${renamed}` }),
			).toBeVisible({ timeout: 15_000 });
		} finally {
			await o.ctx.close();
		}

		const row = await readRow(
			'the renamed group',
			getAdminClient().from('conversations').select('title').eq('id', groupId).single(),
		);
		expect(row.title).toBe(renamed);
		const lines = await readRows(
			'the rename line',
			getAdminClient()
				.from('direct_messages')
				.select('sender_id, body')
				.eq('conversation_id', groupId)
				.eq('kind', 'group_renamed'),
		);
		expect(lines).toEqual([{ sender_id: owner.id, body: renamed }]);

		const a = await openAs(browser, ann);
		try {
			await a.page.goto(`/messages/group/${groupId}`);
			await expect(a.page.getByTestId('group-title')).toHaveText(renamed, { timeout: 15_000 });
			await expect(
				a.page
					.getByTestId('group-renamed-line')
					.filter({ hasText: `${owner.displayName} renamed the group to ${renamed}` }),
			).toBeVisible({ timeout: 15_000 });
		} finally {
			await a.ctx.close();
		}
	});

	test('the invite panel invites someone from the follow graph', async ({ browser }) => {
		const invitee = fillers[5];
		const o = await openAs(browser, owner);
		try {
			const sheet = await openSheet(o.page);
			await sheet.getByTestId('group-invite-more').click();
			const panel = sheet.getByTestId('group-invite-panel');
			await expect(panel.getByTestId('group-people-count')).toHaveText('0 of 23 selected', { timeout: 10_000 });
			// Members and live invitations are not offered again.
			for (const taken of [ann, ben, cid, fillers[0]]) {
				await expect(panel.locator(`[data-testid="group-person"][data-user-id="${taken.id}"]`)).toHaveCount(0);
			}
			await panel.locator(`[data-testid="group-person"][data-user-id="${invitee.id}"]`).check();
			await expect(panel.getByTestId('group-people-count')).toHaveText('1 of 23 selected');
			await panel.getByTestId('group-invite-send').click();
			await expect(sheet.getByTestId('group-invite-panel')).toHaveCount(0, { timeout: 10_000 });
			await expect(memberRow(o.page, invitee)).toHaveAttribute('data-role', 'invited', { timeout: 10_000 });
			await expect(memberRow(o.page, invitee)).toContainText(invitee.displayName);
		} finally {
			await o.ctx.close();
		}

		const row = await readRow(
			'the new invitation',
			getAdminClient()
				.from('conversation_participants')
				.select('membership_state, invited_by, role')
				.eq('conversation_id', groupId)
				.eq('user_id', invitee.id)
				.single(),
		);
		expect(row).toEqual({ membership_state: 'invited', invited_by: owner.id, role: null });
	});

	test('the picker searches, and stops at 32 seats counting live invitations', async ({ browser }) => {
		// Four members and six invitations hold ten seats; 24 followees are free.
		const o = await openAs(browser, owner);
		try {
			const sheet = await openSheet(o.page);
			await sheet.getByTestId('group-invite-more').click();
			const panel = sheet.getByTestId('group-invite-panel');
			const people = panel.getByTestId('group-person');
			await expect(panel.getByTestId('group-people-count')).toHaveText('0 of 22 selected', { timeout: 10_000 });
			await expect(people).toHaveCount(FILLERS - 6);

			const search = panel.getByTestId('group-people-search');
			await search.fill(`pacer ${stamp} 1`);
			await expect(people).toHaveCount(10);
			for (const i of [10, 15, 19]) {
				await expect(panel.locator(`[data-testid="group-person"][data-user-id="${fillers[i].id}"]`)).toBeVisible();
			}
			await search.fill(ann.displayName);
			await expect(people).toHaveCount(0);
			await expect(panel).toContainText('No one matches that name.');
			await search.fill('');
			await expect(people).toHaveCount(FILLERS - 6);

			const free = fillers.slice(6);
			for (const f of free.slice(0, 22)) {
				await panel.locator(`[data-testid="group-person"][data-user-id="${f.id}"]`).check();
			}
			await expect(panel.getByTestId('group-people-count')).toHaveText('22 of 22 selected');
			await expect(panel.getByTestId('group-people-full')).toBeVisible();
			for (const f of free.slice(22)) {
				const box = panel.locator(`[data-testid="group-person"][data-user-id="${f.id}"]`);
				await expect(box).toBeDisabled();
				await expect(box).not.toBeChecked();
			}
			// Unticking one frees its seat again.
			await panel.locator(`[data-testid="group-person"][data-user-id="${free[0].id}"]`).uncheck();
			await expect(panel.getByTestId('group-people-full')).toHaveCount(0);
			await expect(panel.locator(`[data-testid="group-person"][data-user-id="${free[22].id}"]`)).toBeEnabled();
			await panel.locator(`[data-testid="group-person"][data-user-id="${free[0].id}"]`).check();
			await expect(panel.getByTestId('group-people-full')).toBeVisible();

			await panel.getByTestId('group-invite-send').click();
			await expect(sheet.getByTestId('group-invite-panel')).toHaveCount(0, { timeout: 10_000 });
			await expect(sheet.getByTestId('group-member')).toHaveCount(32, { timeout: 10_000 });
			await expect(sheet.getByTestId('group-invite-more')).toBeDisabled();
		} finally {
			await o.ctx.close();
		}

		const roster = await roles();
		expect(roster.size).toBe(32);
		for (const f of fillers.slice(6, 28)) expect(roster.has(f.id)).toBe(true);
		for (const f of fillers.slice(28)) expect(roster.has(f.id)).toBe(false);
	});

	test('ownership moves only through its confirm, and the old owner loses the owner controls', async ({
		browser,
	}) => {
		const o = await openAs(browser, owner);
		try {
			await openSheet(o.page);
			await memberRow(o.page, ben).getByTestId('group-member-transfer').click();
			const confirm = o.page.getByTestId('group-transfer-confirm');
			await expect(confirm).toContainText(`Make ${ben.displayName} the owner?`);
			await confirm.getByRole('button', { name: 'Cancel', exact: true }).click();
			await expect(confirm).toBeHidden();
			await expect(memberRow(o.page, owner)).toHaveAttribute('data-role', 'owner');
			let roster = await roles();
			expect(roster.get(owner.id)).toBe('owner');
			expect(roster.get(ben.id)).toBe('member');

			await memberRow(o.page, ben).getByTestId('group-member-transfer').click();
			await confirm.getByRole('button', { name: 'Make owner', exact: true }).click();
			await expect(memberRow(o.page, ben)).toHaveAttribute('data-role', 'owner', { timeout: 10_000 });
			await expect(memberRow(o.page, owner)).toHaveAttribute('data-role', 'admin');
			roster = await roles();
			expect(roster.get(ben.id)).toBe('owner');
			expect(roster.get(owner.id)).toBe('admin');

			await o.page.reload();
			const sheet = await openSheet(o.page);
			await expect(memberRow(o.page, ben)).toHaveAttribute('data-role', 'owner');
			await expect(sheet.getByTestId('group-member-promote')).toHaveCount(0);
			await expect(sheet.getByTestId('group-member-demote')).toHaveCount(0);
			await expect(sheet.getByTestId('group-member-transfer')).toHaveCount(0);
			await expect(memberRow(o.page, ben).getByTestId('group-member-remove')).toHaveCount(0);
			// Still an admin: manages the group and removes a plain member.
			await expect(sheet.getByTestId('group-rename')).toBeVisible();
			await expect(memberRow(o.page, cid).getByTestId('group-member-remove')).toBeVisible();
		} finally {
			await o.ctx.close();
		}

		const b = await openAs(browser, ben);
		try {
			await openSheet(b.page);
			await expect(memberRow(b.page, owner).getByTestId('group-member-demote')).toBeVisible();
			await expect(memberRow(b.page, cid).getByTestId('group-member-promote')).toBeVisible();
			await expect(memberRow(b.page, cid).getByTestId('group-member-transfer')).toBeVisible();
		} finally {
			await b.ctx.close();
		}
	});
});
