import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { browserDayAt } from '../fixtures/dates';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /social?tab=feed — badge awards from people you follow are rows of the
 * feed, one per person per day, placed by time (feed_highlights.ts; issue
 * #1374). They replaced a strip of sentence-length chips above the feed.
 *
 * The followee-awards read is answered from a fixture so the rows, their
 * days and their order are deterministic; the run they sit around is real.
 */

const award = (id: string, earnedAt: string, badgeKey = 'streak', tier = 'gold') => ({
	id,
	user_id: USER_A.id,
	badge_key: badgeKey,
	tier,
	source_kind: badgeKey,
	source_id: null,
	value_num: null,
	is_public: true,
	earned_at: earnedAt,
});

test.describe('/social?tab=feed — badge highlights', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let runId: string | null = null;

	test.beforeEach(async () => {
		await getAdminClient()
			.from('user_follows')
			.upsert({ follower_id: USER_B.id, followee_id: USER_A.id }, { onConflict: 'follower_id,followee_id' });
	});

	test.afterEach(async () => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
			runId = null;
		}
	});

	test('highlights sit in the feed by time, grouped per person per day, and open the badges', async ({
		page,
		mockRoute,
	}) => {
		const title = `E2E feed-highlights ${Date.now()}`;
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: browserDayAt(-2, 12),
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true,
			metadata: { activity_type: 'run', title },
		});

		const single = award('00000000-0000-4000-8000-0000000000f1', browserDayAt(-1, 18));
		const day = [
			award('00000000-0000-4000-8000-0000000000f2', browserDayAt(-2, 11), 'park_courses', 'bronze'),
			award('00000000-0000-4000-8000-0000000000f3', browserDayAt(-2, 10)),
			award('00000000-0000-4000-8000-0000000000f4', browserDayAt(-2, 9), 'streak', 'silver'),
		];
		await mockRoute(page, '**/rest/v1/achievements*', async (route) => {
			const url = route.request().url();
			if (!url.includes('user_id=in.')) return route.fallback();
			const body = url.includes('or=') ? [] : [single, ...day];
			await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
		});

		await page.goto('/social?tab=feed');
		const runCard = page.locator('article.entry').filter({ hasText: title });
		await expect(runCard).toBeVisible({ timeout: 10_000 });

		const highlights = page.getByTestId('feed-highlight');
		await expect(highlights).toHaveCount(2);
		await expect(highlights.nth(0)).toContainText(/earned the .* badge/);
		await expect(highlights.nth(1)).toContainText(/earned 3 badges/);

		// One vertical list, in time order: the newer award, the run, then the
		// day of three. No sideways strip remains.
		await expect(page.locator('.badge-strip')).toHaveCount(0);
		const order = await page.locator('.feed').evaluate((feed, runTitle) => {
			const kids = Array.from(feed.children);
			const idx = (pred: (el: Element) => boolean) => kids.findIndex(pred);
			const hl = kids.filter((el) => el.getAttribute('data-testid') === 'feed-highlight').map((el) => kids.indexOf(el));
			return { run: idx((el) => el.textContent?.includes(runTitle) ?? false), hl };
		}, title);
		expect(order.hl[0]).toBeLessThan(order.run);
		expect(order.hl[1]).toBeGreaterThan(order.run);

		await expect(highlights.nth(0).getByRole('link')).toHaveAttribute(
			'href',
			`/u/${USER_A.id}?tab=achievements&badge=${single.id}`
		);
		await expect(highlights.nth(1).getByRole('link')).toHaveAttribute('href', `/u/${USER_A.id}?tab=achievements`);
	});

	test('an activity chip hides the highlights and All brings them back', async ({ page, mockRoute }) => {
		await mockRoute(page, '**/rest/v1/achievements*', async (route) => {
			const url = route.request().url();
			if (!url.includes('user_id=in.')) return route.fallback();
			const body = url.includes('or=') ? [] : [award('00000000-0000-4000-8000-0000000000f5', browserDayAt(-1, 18))];
			await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
		});

		await page.goto('/social?tab=feed');
		const highlights = page.getByTestId('feed-highlight');
		await expect(highlights).toHaveCount(1, { timeout: 10_000 });

		await page.getByRole('group', { name: /activity/i }).getByRole('button', { name: 'Run', exact: true }).click();
		await expect(highlights).toHaveCount(0);

		await page.getByRole('group', { name: /activity/i }).getByRole('button', { name: 'All', exact: true }).click();
		await expect(highlights).toHaveCount(1);
	});
});
