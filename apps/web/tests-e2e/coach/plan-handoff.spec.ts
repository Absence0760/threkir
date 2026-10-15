import { expect, test } from '../fixtures/mock-route';

import { USER_A } from '../fixtures/users';

/**
 * /coach → the AI plan assistant handoff (decisions § 1930). The coach never
 * writes a plan; with the assistant live, a new chat offers a plan-building
 * chip, and the coach's reply carries one `/plans/new?describe=…` link that
 * drops the runner on the wizard with the description filled in.
 *
 * The active thread is stubbed empty so the primer renders regardless of what
 * other specs left in USER_A's no-plan thread. `/coach?plan=none` with
 * USER_A's seeded runs selects the no-plan suggestion set.
 */
test.describe('/coach — plan handoff', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	async function emptyActiveThread(
		page: import('@playwright/test').Page,
		mockRoute: (
			target: import('@playwright/test').Page,
			url: string,
			handler: (route: import('@playwright/test').Route) => unknown
		) => Promise<unknown>
	) {
		await mockRoute(page, '**/rest/v1/coach_messages?*archived_at=is.null*', async (route) => {
			if (route.request().method() !== 'GET') return route.fallback();
			await route.fulfill({ status: 200, contentType: 'application/json', body: '[]' });
		});
	}

	test('a new chat offers the plan-building chip first, and it fills the composer', async ({
		page,
		mockRoute
	}) => {
		await emptyActiveThread(page, mockRoute);
		await page.goto('/coach?plan=none');

		const chips = page.locator('.primer .suggest');
		await expect(chips.first()).toHaveText('Build me a half marathon training plan', {
			timeout: 10_000
		});
		await expect(chips).toHaveCount(4);

		await chips.first().click();
		await expect(page.getByPlaceholder(/Ask about today/)).toHaveValue(
			'Build me a half marathon training plan'
		);
	});
});
