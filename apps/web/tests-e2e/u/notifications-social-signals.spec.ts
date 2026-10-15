import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { clearNotifications } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * The inbox and bell lines for the three social signals of decisions § 1971:
 * `reaction`, `comment_like` and `mention`. Rows are planted with the service
 * role in the shape the notify triggers write them; the triggers and their
 * gates are pgTAP's (run_reactions_likes_mentions*_test.sql). What is under
 * test is that each kind reads its own sentence with the actor's name and that
 * the line opens the run it names.
 */

const ACTOR = 'Alex Chen';
const LINES = {
	reaction: `${ACTOR} reacted to your run`,
	comment_like: `${ACTOR} liked your comment`,
	mention: `${ACTOR} mentioned you in a comment`,
};

test.describe('social-signal notification lines', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		await clearNotifications(USER_A.id);
		const { error } = await getAdminClient()
			.from('notifications')
			.insert(
				Object.keys(LINES).map((kind) => ({
					user_id: USER_A.id,
					actor_id: USER_B.id,
					kind,
					run_id: RUNNER_PUBLIC_RUN_ID,
					activity_kind: 'run',
					activity_id: RUNNER_PUBLIC_RUN_ID,
				})),
			);
		if (error) throw new Error(`notification insert failed: ${error.message}`);
	});

	test.afterEach(async () => {
		await clearNotifications(USER_A.id);
	});

	test('the inbox reads each kind as itself, and a mention opens its run', async ({ page }) => {
		await page.goto(`/u/${USER_A.id}?tab=notifications`);
		const items = page.locator('.item-wrap');
		await expect(items.first()).toBeVisible({ timeout: 10_000 });
		await expect(items).toHaveCount(3);
		for (const line of Object.values(LINES)) {
			await expect(items.filter({ hasText: line })).toHaveCount(1);
		}

		await items.filter({ hasText: LINES.mention }).locator('.item-main').click();
		await expect(page).toHaveURL(new RegExp(`/runs/${RUNNER_PUBLIC_RUN_ID}$`), { timeout: 10_000 });
	});

	test('the bell carries the same three lines', async ({ page }) => {
		await page.goto('/dashboard');
		await expect(page.locator('.bell-wrap .badge')).toHaveText('3', { timeout: 10_000 });

		await page.locator('.bell-wrap .bell-btn').click();
		const popover = page.locator('.bell-wrap [role="dialog"]');
		await expect(popover).toBeVisible({ timeout: 5_000 });
		for (const line of Object.values(LINES)) {
			await expect(popover).toContainText(line);
		}
	});
});
