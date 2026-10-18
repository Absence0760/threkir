import { expect, test } from '../fixtures/test';

import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * The profile header's Runs count. It used to be the length of the loaded
 * run page, which caps at 20, so a runner with more public runs read as 20 —
 * and an owner whose runs were mostly private saw a small number with nothing
 * saying the rest exist. 25 public runs clear the page cap; 3 private ones
 * are what the owner (and only the owner) is told about.
 */
test.describe('profile run counts', () => {
	test.describe.configure({ timeout: 90_000 });

	const PUBLIC_RUNS = 25;
	const PRIVATE_RUNS = 3;
	let users: SagaUser[];
	let owner: SagaUser;
	let viewer: SagaUser;

	test.beforeAll(async () => {
		const stamp = Date.now().toString(36);
		users = await createSagaUsers(2, {
			displayNames: [`RunCounts Owner ${stamp}`, `RunCounts Viewer ${stamp}`],
		});
		[owner, viewer] = users;
		const hour = 60 * 60 * 1000;
		await Promise.all(
			Array.from({ length: PUBLIC_RUNS + PRIVATE_RUNS }, (_, i) =>
				insertRun({
					user_id: owner.id,
					started_at: new Date(Date.now() - (i + 1) * 24 * hour).toISOString(),
					distance_m: 5_000,
					duration_s: 1_800,
					is_public: i < PUBLIC_RUNS,
				}),
			),
		);
	});

	test.afterAll(async () => {
		if (users) await deleteSagaUsers(users);
	});

	async function pageFor(browser: import('@playwright/test').Browser, user: SagaUser) {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		return { ctx, page: await ctx.newPage() };
	}

	test('the owner sees the true public count and is told about the private runs', async ({ browser }) => {
		const { ctx, page } = await pageFor(browser, owner);
		await page.goto(`/u/${owner.id}`);
		await expect(page.getByTestId('profile-run-count')).toHaveText(String(PUBLIC_RUNS));
		const note = page.getByTestId('profile-private-runs-note');
		await expect(note).toContainText(`${PRIVATE_RUNS} of your runs aren't public`);
		await expect(note.getByRole('link', { name: 'View all in Runs' })).toHaveAttribute('href', '/runs?view=list');
		await ctx.close();
	});

	test('another runner sees the same public count and no private-runs note', async ({ browser }) => {
		const { ctx, page } = await pageFor(browser, viewer);
		await page.goto(`/u/${owner.id}`);
		await expect(page.getByTestId('profile-run-count')).toHaveText(String(PUBLIC_RUNS));
		await expect(page.locator('.run-card').first()).toBeVisible();
		await expect(page.getByTestId('profile-private-runs-note')).toHaveCount(0);
		await ctx.close();
	});
});
