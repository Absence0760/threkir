import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * /social — top-level social hub page chrome: ARIA tab strip with
 * Feed · Clubs · Events · Challenges · People in that order (issue #1374),
 * ?tab= URL state, the Events tab's old `?tab=discover` URL, and the two
 * legacy URLs (/clubs, /feed) that redirect here. Per-tab specs live
 * in social/people.spec.ts, social/feed.spec.ts and social/discover.spec.ts.
 */

test.describe('/social — tab strip + redirects', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('default lands on Feed tab; clicking People updates ?tab and aria-selected', async ({
		page
	}) => {
		await page.goto('/social');
		await expect(page.getByRole('heading', { level: 1, name: 'Social' })).toBeVisible({
			timeout: 10_000
		});
		const feedTab = page.getByRole('tab', { name: /Feed/ });
		const peopleTab = page.getByRole('tab', { name: /People/ });
		const clubsTab = page.getByRole('tab', { name: /Clubs/ });
		await expect(feedTab).toHaveAttribute('aria-selected', 'true');
		await expect(peopleTab).toHaveAttribute('aria-selected', 'false');
		await expect(clubsTab).toHaveAttribute('aria-selected', 'false');

		await peopleTab.click();
		await expect(page).toHaveURL(/\/social\?tab=people/, { timeout: 5_000 });
		await expect(peopleTab).toHaveAttribute('aria-selected', 'true');
		await expect(feedTab).toHaveAttribute('aria-selected', 'false');

		await clubsTab.click();
		await expect(page).toHaveURL(/\/social\?tab=clubs/, { timeout: 5_000 });
		await expect(clubsTab).toHaveAttribute('aria-selected', 'true');
	});

	test('the strip reads Feed · Clubs · Events · Challenges · People', async ({ page }) => {
		await page.goto('/social');
		const tabs = page.getByRole('tablist', { name: 'Social sections' }).getByRole('tab');
		const order = ['Feed', 'Clubs', 'Events', 'Challenges', 'People'];
		await expect(tabs).toHaveCount(order.length, { timeout: 10_000 });
		// The accessible name, not the text: each tab's icon ligature is in its
		// text but hidden from the name.
		for (const [i, name] of order.entries()) {
			await expect(tabs.nth(i)).toHaveAccessibleName(name);
		}
		await expect(page.getByRole('tab', { name: /Discover/ })).toHaveCount(0);
	});

	test('the Events tab opens the activity search at ?tab=events', async ({ page }) => {
		await page.goto('/social');
		const eventsTab = page.getByRole('tab', { name: /Events/ });
		await eventsTab.click();
		await expect(page).toHaveURL(/\/social\?tab=events/, { timeout: 5_000 });
		await expect(eventsTab).toHaveAttribute('aria-selected', 'true');
		await expect(page.getByTestId('discover-search')).toBeVisible();
	});

	test('the old ?tab=discover URL lands on Events and is rewritten', async ({ page }) => {
		await page.goto('/social?tab=discover');
		await expect(page).toHaveURL(/\/social\?tab=events/, { timeout: 10_000 });
		await expect(page.getByRole('tab', { name: /Events/ })).toHaveAttribute(
			'aria-selected',
			'true'
		);
		await expect(page.getByTestId('discover-search')).toBeVisible();
	});

	test('/clubs (top-level) redirects to /social?tab=clubs', async ({ page }) => {
		await page.goto('/clubs');
		await expect(page).toHaveURL(/\/social\?tab=clubs/, { timeout: 10_000 });
	});

	test('/clubs?tab=browse redirects to /social?tab=clubs&clubs-sub=browse (deep link preserved)', async ({
		page
	}) => {
		await page.goto('/clubs?tab=browse');
		await expect(page).toHaveURL(/\/social\?tab=clubs&clubs-sub=browse/, {
			timeout: 10_000
		});
	});

	test('/feed redirects to /social?tab=feed', async ({ page }) => {
		await page.goto('/feed');
		await expect(page).toHaveURL(/\/social\?tab=feed/, { timeout: 10_000 });
	});

	test('/social?tab=clubs renders the My-clubs sub-tab (canary: club card visible)', async ({
		page
	}) => {
		await page.goto('/social?tab=clubs');
		// Runner owns / admins Richmond Run Club in the seed.
		await expect(
			page.locator('.card', { hasText: 'Richmond Run Club' }).first()
		).toBeVisible({ timeout: 10_000 });
	});
});
