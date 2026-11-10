import { AI_DISCLOSURE_CURRENT_VERSION } from '../../src/lib/core/ai_disclosure';
import type { Browser } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Share with coach (issue #1215 Phase 3, migration 20271210001215).
 *
 * Two saga users: an athlete with AI consent and one Coach answer, and a
 * coach. seed.sql opens the coach_share gate. In order:
 *
 *   1. Without an active coaching link the answer offers no share action.
 *   2. With one, the athlete picks two of the answer's three paragraphs and
 *      shares them; the card in the thread is labelled AI, holds exactly
 *      those paragraphs, offers no Edit, and links back to the AI Coach.
 *   3. The coach reads the same card, labelled AI and attributed to the
 *      athlete, with the answer's markup drawn as text and no link back.
 */
test.describe.configure({ mode: 'serial', timeout: 90_000 });

test.describe('Messages — share an AI Coach answer with your coach', () => {
	const admin = getAdminClient();
	let athlete: SagaUser;
	let coach: SagaUser;
	const stamp = Date.now();
	const answer = [
		`## Week plan ${stamp}`,
		`Keep **Tuesday** easy <img src=x onerror="window.__pwned=1">`,
		`Skip the hills ${stamp}`,
	].join('\n\n');

	test.beforeAll(async () => {
		[athlete, coach] = await createSagaUsers(2, {
			displayNames: ['Share Athlete Saga', 'Share Coach Saga'],
		});
		const client = await getUserClient({ email: athlete.email, password: athlete.password });
		const { error: consentErr } = await client.rpc('record_ai_disclosure_consent', {
			p_version: AI_DISCLOSURE_CURRENT_VERSION,
		});
		if (consentErr) throw consentErr;
		const { error } = await admin.from('coach_messages').insert([
			{ user_id: athlete.id, plan_id: null, role: 'user', content: `What now ${stamp}?` },
			{ user_id: athlete.id, plan_id: null, role: 'assistant', content: answer },
		]);
		if (error) throw error;
	});

	test.afterAll(async () => {
		if (athlete && coach) {
			await admin.from('coach_athletes').delete().eq('coach_id', coach.id);
			await deleteSagaUsers([athlete, coach]);
		}
	});

	const as = async (browser: Browser, user: SagaUser) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		return { ctx, page: await ctx.newPage() };
	};

	test('no share action without an active coach', async ({ browser }) => {
		const { ctx, page } = await as(browser, athlete);
		await page.goto('/messages/coach?plan=none');
		await expect(page.locator('.bubble[data-role="assistant"]')).toHaveCount(1, { timeout: 15_000 });
		await expect(page.locator('.bubble[data-role="assistant"] .bubble-actions')).toBeVisible();
		await expect(page.getByTestId('coach-share-action')).toHaveCount(0);
		await ctx.close();
	});

	test('the athlete shares two paragraphs and the card is labelled AI', async ({ browser }) => {
		const { error: linkErr } = await admin.from('coach_athletes').insert({
			coach_id: coach.id,
			athlete_id: athlete.id,
			status: 'active',
			invite_token: `e2e-coach-share-${stamp}`,
			accepted_at: new Date().toISOString(),
		});
		expect(linkErr).toBeNull();

		const { ctx, page } = await as(browser, athlete);
		await page.goto('/messages/coach?plan=none');
		await page.getByTestId('coach-share-action').click();
		const dialog = page.getByTestId('coach-share-dialog');
		await expect(dialog).toBeVisible();
		await expect(dialog).toContainText('Sending to Share Coach Saga');
		const paragraphs = dialog.getByTestId('coach-share-paragraph');
		await expect(paragraphs).toHaveCount(3);
		await paragraphs.nth(1).getByRole('checkbox').uncheck();
		await dialog.getByTestId('coach-share-send').click();
		await expect(dialog.getByTestId('coach-share-sent')).toHaveText('Shared with Share Coach Saga.');

		const { data: rows } = await admin
			.from('direct_messages')
			.select('kind, body, coach_message_id')
			.eq('sender_id', athlete.id)
			.eq('recipient_id', coach.id);
		expect(rows).toHaveLength(1);
		expect(rows![0].kind).toBe('coach_share');
		expect(rows![0].body).toBe(`## Week plan ${stamp}\n\nSkip the hills ${stamp}`);
		expect(rows![0].coach_message_id).not.toBeNull();

		await dialog.getByRole('link', { name: 'Open conversation' }).click();
		await expect(page).toHaveURL(new RegExp(`/messages/${coach.id}$`));
		const card = page.getByTestId('dm-coach-share');
		await expect(card).toBeVisible({ timeout: 15_000 });
		await expect(card.getByTestId('ai-tag')).toContainText('AI-generated');
		await expect(card).toContainText('You shared this from your AI Coach');
		await expect(card).toContainText(`Skip the hills ${stamp}`);
		await expect(card).not.toContainText('Tuesday');
		await expect(page.getByTestId('dm-edit')).toHaveCount(0);
		await expect(card.getByTestId('dm-coach-share-source')).toHaveAttribute('href', '/messages/coach');
		await ctx.close();
	});

	test('the coach reads the card as AI text, markup drawn as text', async ({ browser }) => {
		const client = await getUserClient({ email: athlete.email, password: athlete.password });
		const { data: source } = await client.from('coach_messages').select('id').eq('role', 'assistant').single();
		const { error } = await client.rpc('share_coach_message', {
			p_coach_message_id: source!.id,
			p_coach_id: coach.id,
			p_paragraphs: [1],
		});
		expect(error).toBeNull();

		const { ctx, page } = await as(browser, coach);
		await page.goto(`/messages/${athlete.id}`);
		const cards = page.getByTestId('dm-coach-share');
		await expect(cards).toHaveCount(2, { timeout: 15_000 });
		const last = cards.last();
		await expect(last.getByTestId('ai-tag')).toContainText('AI-generated');
		await expect(last).toContainText('Share Athlete Saga shared this from their AI Coach');
		await expect(last.locator('strong')).toHaveText('Tuesday');
		await expect(last).toContainText('<img src=x onerror="window.__pwned=1">');
		await expect(last.locator('img')).toHaveCount(0);
		expect(await page.evaluate(() => (window as unknown as { __pwned?: number }).__pwned)).toBeUndefined();
		await expect(page.getByTestId('dm-coach-share-source')).toHaveCount(0);
		const row = page.locator('.threads a.thread', { hasText: 'Share Athlete Saga' });
		await expect(row.getByTestId('ai-tag')).toBeVisible();
		await ctx.close();
	});
});
