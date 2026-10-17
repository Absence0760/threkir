import type { Page, Route } from '@playwright/test';

import { expect, test } from '../fixtures/test';
import type { MockRoute } from '../fixtures/mock-route';
import { USER_A } from '../fixtures/users';

/**
 * /plans — the card states that the seed cannot reach on its own: a paused
 * plan, a custom-distance goal and an empty list. The list read is rewritten
 * in flight, so the shared seed plan ("Richmond Half 2026") is never mutated.
 */
test.describe('/plans card states', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const SEED_PLAN = 'Richmond Half 2026';

	function isListRead(url: URL): boolean {
		return (
			url.pathname.endsWith('/rest/v1/training_plans') &&
			url.searchParams.get('is_template') === 'eq.false' &&
			url.searchParams.get('select') === '*'
		);
	}

	async function rewriteList(
		page: Page,
		mockRoute: MockRoute,
		rewrite: (rows: Array<Record<string, unknown>>) => Array<Record<string, unknown>>
	) {
		await mockRoute(page, isListRead, async (route: Route) => {
			if (route.request().method() !== 'GET') return route.fallback();
			const response = await route.fetch();
			const rows = (await response.json()) as Array<Record<string, unknown>>;
			await route.fulfill({ response, json: rewrite(rows) });
		});
	}

	test('a paused plan offers Abandon, not Delete, and the confirm says what is kept', async ({
		page,
		mockRoute
	}) => {
		await rewriteList(page, mockRoute, (rows) =>
			rows.map((r) => (r.name === SEED_PLAN ? { ...r, status: 'paused' } : r))
		);
		await page.goto('/plans');

		const card = page.locator('.card', { hasText: SEED_PLAN });
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card.locator('.badge')).toHaveText(/paused/i);
		await expect(card.getByRole('button', { name: 'Delete' })).toHaveCount(0);

		await card.getByRole('button', { name: 'Abandon' }).click();
		const dialog = page.locator('.modal', { hasText: 'Abandon plan' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await expect(dialog).toContainText('Its weeks, workouts and linked runs are kept.');
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(dialog).toHaveCount(0);
	});

	test('a custom-distance plan names its distance instead of "Custom"', async ({
		page,
		mockRoute
	}) => {
		await rewriteList(page, mockRoute, (rows) =>
			rows.map((r) =>
				r.name === SEED_PLAN ? { ...r, goal_event: 'custom', goal_distance_m: 50_000 } : r
			)
		);
		await page.goto('/plans');

		const card = page.locator('.card', { hasText: SEED_PLAN });
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card.locator('.hero-value').first()).toHaveText(/^(50\.00 km|31\.07 mi)$/);
	});

	test('an empty list offers the three built-in starters and when they begin', async ({
		page,
		mockRoute
	}) => {
		await rewriteList(page, mockRoute, () => []);
		await page.goto('/plans');

		const starters = page.getByRole('group', { name: 'Start from a built-in plan' });
		await expect(starters).toBeVisible({ timeout: 10_000 });
		await expect(starters).toContainText(/Each starts on /);
		await expect(starters.getByRole('button')).toHaveText([
			'Couch to 5K (beginner walk-run)',
			'Half Marathon — 12 weeks',
			'Marathon — 16 weeks'
		]);
	});
});
