import { expect, test } from '../fixtures/test';

import { readCount, readRows } from '../fixtures/db-read';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { clearNotifications, insertComment } from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * Reactions, comment likes and @mentions on a run (decisions § 1971), driven
 * through the real UI by alex on runner's public run:
 *
 *   1. a reaction chip toggles on, writes the run_reactions row, and runner's
 *      inbox gets one `reaction` row;
 *   2. liking runner's comment writes the run_comment_likes row and notifies
 *      runner with `comment_like`;
 *   3. typing `@` + morgan's handle offers morgan in the picker, the posted
 *      comment draws the handle as a link to morgan's profile, and morgan gets
 *      a `mention` row.
 *
 * The gates (blocks, audience, self-reaction) are pinned in pgtap
 * (run_reactions_likes_mentions_test.sql), against real JWTs.
 */

const MORGAN_HANDLE = 'morgan_e2e_mention';

async function cleanup() {
	const admin = getAdminClient();
	await admin.from('run_reactions').delete().eq('run_id', RUNNER_PUBLIC_RUN_ID).eq('user_id', USER_B.id);
	await admin
		.from('run_comments')
		.delete()
		.eq('run_id', RUNNER_PUBLIC_RUN_ID)
		.like('body', '%[e2e-rlm]%');
	await clearNotifications(USER_A.id);
	await clearNotifications(USER_C_PRO.id);
}

test.describe('run reactions, comment likes and mentions', () => {
	test.describe.configure({ mode: 'serial', timeout: 90_000 });

	let morganPreviousHandle: string | null = null;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data } = await admin
			.from('user_profiles')
			.select('handle')
			.eq('id', USER_C_PRO.id)
			.single();
		morganPreviousHandle = (data?.handle as string | null) ?? null;
		await admin.from('user_profiles').update({ handle: MORGAN_HANDLE }).eq('id', USER_C_PRO.id);
	});

	test.afterAll(async () => {
		await getAdminClient()
			.from('user_profiles')
			.update({ handle: morganPreviousHandle })
			.eq('id', USER_C_PRO.id);
	});

	test.beforeEach(cleanup);
	test.afterEach(cleanup);

	test('a reaction toggles on and notifies the run owner once', async ({ browser, mockRoute }) => {
		const ctx = await browser.newContext({ storageState: USER_B.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		try {
			await mockRoute(page, '**/functions/v1/clip-public-track', (route) =>
				route.fulfill({ status: 200, contentType: 'application/json', body: '{"points":[]}' }),
			);
			await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
			const fire = page.locator('[data-testid="run-reactions"] [data-reaction="fire"]');
			await expect(fire).toBeVisible({ timeout: 10_000 });
			await expect(fire).toHaveAttribute('aria-pressed', 'false');
			await fire.click();
			await expect(fire).toHaveAttribute('aria-pressed', 'true', { timeout: 10_000 });
			await expect(fire.locator('.reaction-count')).toHaveText('1');

			const admin = getAdminClient();
			const rows = await readRows(
				'alex reactions',
				admin
				.from('run_reactions')
				.select('reaction')
				.eq('run_id', RUNNER_PUBLIC_RUN_ID)
				.eq('user_id', USER_B.id));
			expect(rows?.map((r) => r.reaction)).toEqual(['fire']);

			// Toggling off and on again does not stack a second notification.
			await fire.click();
			await expect(fire).toHaveAttribute('aria-pressed', 'false', { timeout: 10_000 });
			await fire.click();
			await expect(fire).toHaveAttribute('aria-pressed', 'true', { timeout: 10_000 });
			const count = await readCount(
				'reaction notifications',
				admin
				.from('notifications')
				.select('id', { count: 'exact', head: true })
				.eq('user_id', USER_A.id)
				.eq('actor_id', USER_B.id)
				.eq('kind', 'reaction'));
			expect(count).toBe(1);
		} finally {
			await ctx.close();
		}
	});

	test('liking a comment writes the like and notifies its author', async ({ browser, mockRoute }) => {
		const commentId = await insertComment({
			run_id: RUNNER_PUBLIC_RUN_ID,
			author_id: USER_A.id,
			body: 'thanks for the company [e2e-rlm]',
		});
		await clearNotifications(USER_A.id);
		const ctx = await browser.newContext({ storageState: USER_B.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		try {
			await mockRoute(page, '**/functions/v1/clip-public-track', (route) =>
				route.fulfill({ status: 200, contentType: 'application/json', body: '{"points":[]}' }),
			);
			await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
			const comment = page.locator('.comment').filter({ hasText: 'thanks for the company' });
			const like = comment.locator('[data-testid="comment-like"]').first();
			await expect(like).toBeVisible({ timeout: 10_000 });
			await like.click();
			await expect(like).toHaveAttribute('aria-pressed', 'true', { timeout: 10_000 });

			const admin = getAdminClient();
			const likes = await readCount(
				'comment likes',
				admin
				.from('run_comment_likes')
				.select('user_id', { count: 'exact', head: true })
				.eq('comment_id', commentId)
				.eq('user_id', USER_B.id));
			expect(likes).toBe(1);
			const notes = await readCount(
				'comment-like notifications',
				admin
				.from('notifications')
				.select('id', { count: 'exact', head: true })
				.eq('user_id', USER_A.id)
				.eq('kind', 'comment_like')
				.eq('comment_id', commentId));
			expect(notes).toBe(1);
		} finally {
			await ctx.close();
		}
	});

	test('the mention picker inserts a handle, the comment links it, and the runner is notified', async ({
		browser,
		mockRoute,
	}) => {
		const ctx = await browser.newContext({ storageState: USER_B.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		try {
			await mockRoute(page, '**/functions/v1/clip-public-track', (route) =>
				route.fulfill({ status: 200, contentType: 'application/json', body: '{"points":[]}' }),
			);
			await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
			const composer = page.locator('.composer textarea');
			await expect(composer).toBeVisible({ timeout: 10_000 });
			await composer.click();
			await composer.pressSequentially('next week with @morgan_e2e');
			const suggestion = page
				.locator('[data-testid="mention-suggestions"] button')
				.filter({ hasText: `@${MORGAN_HANDLE}` });
			await expect(suggestion).toBeVisible({ timeout: 10_000 });
			await suggestion.click();
			await expect(composer).toHaveValue(`next week with @${MORGAN_HANDLE} `);
			await composer.pressSequentially('[e2e-rlm]');
			await page.locator('.composer button[type="submit"]').click();

			const link = page.locator('a.mention', { hasText: `@${MORGAN_HANDLE}` });
			await expect(link).toBeVisible({ timeout: 10_000 });
			await expect(link).toHaveAttribute('href', `/u/${USER_C_PRO.id}`);

			const count = await readCount(
				'mention notifications',
				getAdminClient()
				.from('notifications')
				.select('id', { count: 'exact', head: true })
				.eq('user_id', USER_C_PRO.id)
				.eq('actor_id', USER_B.id)
				.eq('kind', 'mention')
				.eq('run_id', RUNNER_PUBLIC_RUN_ID));
			expect(count).toBe(1);
		} finally {
			await ctx.close();
		}
	});

	test('un-reacting and unliking delete the rows and clear the counts', async ({ browser, mockRoute }) => {
		const commentId = await insertComment({
			run_id: RUNNER_PUBLIC_RUN_ID,
			author_id: USER_A.id,
			body: 'see you at the track [e2e-rlm]',
		});
		const admin = getAdminClient();
		const seeded = await Promise.all([
			admin.from('run_reactions').insert({ user_id: USER_B.id, run_id: RUNNER_PUBLIC_RUN_ID, reaction: 'wave' }),
			admin.from('run_comment_likes').insert({ user_id: USER_B.id, comment_id: commentId }),
		]);
		for (const { error } of seeded) if (error) throw new Error(`seed failed: ${error.message}`);

		const ctx = await browser.newContext({ storageState: USER_B.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		try {
			await mockRoute(page, '**/functions/v1/clip-public-track', (route) =>
				route.fulfill({ status: 200, contentType: 'application/json', body: '{"points":[]}' }),
			);
			await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);

			const wave = page.locator('[data-testid="run-reactions"] [data-reaction="wave"]');
			await expect(wave).toHaveAttribute('aria-pressed', 'true', { timeout: 10_000 });
			await expect(wave.locator('.reaction-count')).toHaveText('1');
			await wave.click();
			await expect(wave).toHaveAttribute('aria-pressed', 'false', { timeout: 10_000 });
			await expect(wave.locator('.reaction-count')).toHaveCount(0);

			const like = page
				.locator('.comment')
				.filter({ hasText: 'see you at the track' })
				.locator('[data-testid="comment-like"]')
				.first();
			await expect(like).toHaveAttribute('aria-pressed', 'true', { timeout: 10_000 });
			await expect(like.locator('.like-count')).toHaveText('1');
			await like.click();
			await expect(like).toHaveAttribute('aria-pressed', 'false', { timeout: 10_000 });
			await expect(like.locator('.like-count')).toHaveCount(0);

			const reactionsLeft = await readCount(
				'alex wave reactions',
				admin
				.from('run_reactions')
				.select('user_id', { count: 'exact', head: true })
				.eq('run_id', RUNNER_PUBLIC_RUN_ID)
				.eq('user_id', USER_B.id)
				.eq('reaction', 'wave'));
			expect(reactionsLeft).toBe(0);
			const likesLeft = await readCount(
				'alex comment likes',
				admin
				.from('run_comment_likes')
				.select('user_id', { count: 'exact', head: true })
				.eq('comment_id', commentId)
				.eq('user_id', USER_B.id));
			expect(likesLeft).toBe(0);
		} finally {
			await ctx.close();
		}
	});
});
