import { AI_DISCLOSURE_CURRENT_VERSION } from '../../src/lib/core/ai_disclosure';
import type { Browser } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * The AI Coach as a pinned conversation in Messages (decisions § 2227).
 *
 * A saga user, because the case that matters most needs a runner with NO AI
 * consent on record, and every seeded user is stamped at the current version.
 * The cases run in order on that one user:
 *
 *   1. Without consent the row is there, pinned and labelled AI, and says
 *      what the Coach is — a Coach message already in the table (written
 *      here by the service role, as the handler writes them) never reaches
 *      the page. The sidebar has no Coach row any more.
 *   2. With consent the row quotes the newest Coach message as plain text,
 *      opens the Coach in the Messages pane on that message's plan, and
 *      every Coach message there carries the AI byline.
 *   3. Unpinning is saved to the settings bag and survives a reload; the
 *      Display setting can hide the row entirely.
 *   4. `/coach` redirects into Messages with its query kept.
 */
test.describe.configure({ mode: 'serial', timeout: 90_000 });

test.describe('Messages — the AI Coach conversation', () => {
	const admin = getAdminClient();
	let user: SagaUser;
	const stamp = Date.now();
	const secret = `e2e coach secret ${stamp}`;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Coach Inbox Saga'] });
		const { error } = await admin.from('coach_messages').insert([
			{ user_id: user.id, plan_id: null, role: 'user', content: `How was my week ${stamp}?` },
			{ user_id: user.id, plan_id: null, role: 'assistant', content: `**${secret}** — keep it easy.` },
		]);
		if (error) throw error;
	});

	test.afterAll(async () => {
		if (user) await deleteSagaUsers([user]);
	});

	// The saga user exists only once beforeAll has run, so each case opens
	// its own context on that user's session.
	const asUser = async (browser: Browser) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		return { ctx, page: await ctx.newPage() };
	};

	test('without AI consent the pinned row names the Coach and quotes nothing', async ({ browser }) => {
		const { ctx, page } = await asUser(browser);
		await page.goto('/messages');
		const row = page.getByTestId('inbox-coach-row');
		await expect(row).toBeVisible({ timeout: 15_000 });
		await expect(row).toHaveAttribute('data-placement', 'pinned');
		await expect(page.locator('.threads a.thread').first()).toHaveAttribute(
			'data-testid',
			'inbox-coach-row'
		);
		await expect(row.getByTestId('ai-tag')).toBeVisible();
		await expect(row.getByTestId('ai-tag')).toContainText('AI-generated');
		await expect(page.getByTestId('inbox-coach-preview')).toHaveText(
			'Ask about your training, your plan or a run.'
		);
		await expect(page.getByText(secret)).toHaveCount(0);

		// The Coach left the sidebar for Messages.
		await expect(page.locator('a.nav-link[href="/messages"]')).toBeVisible();
		await expect(page.locator('a.nav-link[href="/coach"]')).toHaveCount(0);

		// Opening it still asks for consent before any chat renders.
		await row.click();
		await expect(page).toHaveURL(/\/messages\/coach/);
		await expect(page.getByRole('dialog', { name: /Before you/ })).toBeVisible();
		await expect(page.locator('form.composer')).toHaveCount(0);
		await ctx.close();
	});

	test('with consent the row previews the newest Coach message and every AI message is labelled', async ({ browser }) => {
		const { ctx, page } = await asUser(browser);
		const client = await getUserClient({ email: user.email, password: user.password });
		const { error } = await client.rpc('record_ai_disclosure_consent', {
			p_version: AI_DISCLOSURE_CURRENT_VERSION,
		});
		expect(error).toBeNull();
		const later = new Date(Date.now() + 1000).toISOString();
		const { error: insertError } = await admin.from('coach_messages').insert({
			user_id: user.id,
			plan_id: null,
			role: 'assistant',
			content: `## Tomorrow\n- 6 km *easy* ${stamp}`,
			created_at: later,
		});
		expect(insertError).toBeNull();

		await page.goto('/messages');
		const preview = page.getByTestId('inbox-coach-preview');
		await expect(preview).toHaveText(`Tomorrow 6 km easy ${stamp}`, { timeout: 15_000 });

		await page.getByTestId('inbox-coach-row').click();
		await expect(page).toHaveURL(/\/messages\/coach\?plan=none\b/);
		const assistant = page.locator('.bubble[data-role="assistant"]');
		await expect(assistant).toHaveCount(2, { timeout: 15_000 });
		const bylines = page.getByTestId('coach-ai-byline');
		await expect(bylines).toHaveCount(2);
		for (const byline of await bylines.all()) {
			await expect(byline).toContainText('AI Coach');
			await expect(byline.getByTestId('ai-tag')).toContainText('AI-generated');
		}
		// The runner's own turn is not labelled AI.
		await expect(page.locator('.bubble[data-role="user"] [data-testid="ai-tag"]')).toHaveCount(0);
		// The conversation sits beside the inbox, which keeps the row.
		await expect(page.getByTestId('inbox-coach-row')).toHaveClass(/active/);
		await ctx.close();
	});

	test('unpinning is saved and survives a reload; Display can hide the row', async ({ browser }) => {
		const { ctx, page } = await asUser(browser);
		await page.goto('/messages');
		const pin = page.getByTestId('inbox-coach-pin');
		await expect(pin).toHaveAttribute('aria-pressed', 'true', { timeout: 15_000 });
		await expect(pin).toHaveAccessibleName('Unpin AI Coach');
		await pin.click();
		await expect(page.getByTestId('inbox-coach-row')).toHaveAttribute('data-placement', 'listed');
		await expect(pin).toHaveAttribute('aria-pressed', 'false');

		await expect
			.poll(async () => {
				const { data } = await admin
					.from('user_settings')
					.select('prefs')
					.eq('user_id', user.id)
					.maybeSingle();
				return (data?.prefs as Record<string, unknown> | null)?.messages_coach_row ?? null;
			})
			.toBe('listed');

		await page.reload();
		await expect(page.getByTestId('inbox-coach-row')).toHaveAttribute('data-placement', 'listed', {
			timeout: 15_000,
		});
		await expect(page.getByTestId('inbox-coach-pin')).toHaveAccessibleName('Pin AI Coach to the top');

		await page.goto('/settings/display');
		const select = page.getByTestId('coach-in-messages-select');
		await expect(select).toHaveValue('listed', { timeout: 15_000 });
		await select.selectOption('hidden');
		await expect
			.poll(async () => {
				const { data } = await admin
					.from('user_settings')
					.select('prefs')
					.eq('user_id', user.id)
					.maybeSingle();
				return (data?.prefs as Record<string, unknown> | null)?.messages_coach_row ?? null;
			})
			.toBe('hidden');

		await page.goto('/messages');
		await expect(page.getByText('No conversations yet', { exact: false })).toBeVisible({
			timeout: 15_000,
		});
		await expect(page.getByTestId('inbox-coach-row')).toHaveCount(0);
		await ctx.close();
	});

	test('/coach redirects into Messages and keeps its plan', async ({ browser }) => {
		const { ctx, page } = await asUser(browser);
		await page.goto('/coach?plan=none');
		await expect(page).toHaveURL(/\/messages\/coach\?plan=none\b/, { timeout: 15_000 });
		await expect(page.getByRole('heading', { level: 2, name: 'AI Coach' })).toBeVisible();
		await ctx.close();
	});
});
