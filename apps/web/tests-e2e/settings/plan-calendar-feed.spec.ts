import { expect, test } from '../fixtures/test';

import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * /settings/integrations — the subscribable plan calendar link (issue #1186).
 *
 * The URL is the credential, so the card shows a token exactly once, when it
 * is minted; a reload shows only the feed's dates. Replacing it mints a
 * different URL, and turning it off returns the card to its empty state.
 *
 * Runs as a saga user: `rotate_plan_calendar_feed` spends the
 * `plan_calendar_rotate` bucket, and a seeded user's budget is shared with
 * every other spec in the hour (fixtures/rate-limit-budget.test.ts).
 */

const FEED_URL = /\/functions\/v1\/plan-calendar\/[0-9a-f]{96}\.ics$/;

test.describe('plan calendar feed card', () => {
	let users: SagaUser[] = [];

	test.beforeAll(async () => {
		users = await createSagaUsers(1);
	});

	test.afterAll(async () => {
		await deleteSagaUsers(users);
	});

	test('create shows the link once; replace mints a new one; turn off clears it', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: users[0].storageStatePath });
		const page = await ctx.newPage();
		await page.goto('/settings/integrations');

		const card = page.getByTestId('plan-calendar-feed-card');
		await card.getByTestId('plan-calendar-feed-create').click();

		const url = card.getByTestId('plan-calendar-feed-url');
		await expect(url).toHaveValue(FEED_URL);
		const first = await url.inputValue();
		await expect(card.getByTestId('plan-calendar-feed-once')).toBeVisible();

		await page.reload();
		await expect(card.getByTestId('plan-calendar-feed-active')).toBeVisible();
		await expect(card.getByTestId('plan-calendar-feed-url')).toHaveCount(0);
		await expect(card).not.toContainText(first.slice(-96));

		await card.getByTestId('plan-calendar-feed-rotate').click();
		const dialog = page.getByRole('dialog');
		await dialog.getByRole('button', { name: 'Make a new link' }).click();
		await expect(url).toHaveValue(FEED_URL);
		expect(await url.inputValue()).not.toBe(first);

		await card.getByTestId('plan-calendar-feed-revoke').click();
		await page.getByRole('dialog').getByRole('button', { name: 'Turn off' }).click();
		await expect(card.getByTestId('plan-calendar-feed-create')).toBeVisible();

		await page.reload();
		await expect(card.getByTestId('plan-calendar-feed-create')).toBeVisible();
		await ctx.close();
	});
});
