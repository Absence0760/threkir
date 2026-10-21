import type { Page, Route } from '@playwright/test';

import { expect, test } from '../fixtures/test';
import { browserDate } from '../fixtures/dates';
import type { MockRoute } from '../fixtures/mock-route';
import { acceptCookieConsent } from '../fixtures/helpers';
import { USER_A } from '../fixtures/users';

/**
 * /coach "My season" (issue #1213). With a plan queued behind the current one,
 * the plan picker offers the season beside "No plan" and the single plans; the
 * choice survives a reload as `?plan=season`, the thread stays under the
 * current plan, and every request says which scope the runner picked.
 *
 * The plan list read is rewritten in flight so the shared seed plan is never
 * mutated: Richmond Half 2026 is given a window around today and a second
 * plan is queued the day after it ends. The Coach endpoint is stubbed.
 */

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';
const QUEUED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-0000000000e2';

/// Rewrite the plan list read: the seed plan around today, and with `queued`
/// a second plan starting the day after it ends.
async function rewritePlans(page: Page, mockRoute: MockRoute, queued: boolean) {
	await mockRoute(
		page,
		(url) =>
			url.pathname.endsWith('/rest/v1/training_plans') &&
			url.searchParams.get('is_template') === 'eq.false' &&
			url.searchParams.get('select') === '*',
		async (route: Route) => {
			if (route.request().method() !== 'GET') return route.fallback();
			const response = await route.fetch();
			const rows = (await response.json()) as Array<Record<string, unknown>>;
			const seed = rows.find((r) => r.id === SEED_PLAN_ID);
			if (!seed) throw new Error('the seed plan is missing from the list read');
			const current = { ...seed, status: 'active', start_date: browserDate(-14), end_date: browserDate(20) };
			const next = {
				...seed,
				id: QUEUED_PLAN_ID,
				name: 'Autumn ultra block',
				start_date: browserDate(21),
				end_date: browserDate(120),
			};
			await route.fulfill({ response, json: queued ? [next, current] : [current] });
		},
	);
}

function sseBody(reply: string): string {
	return [
		'event: meta',
		`data: ${JSON.stringify({ user_message_id: 'season-user-msg', tier: 'free', limits: { daily_limit: 10 } })}`,
		'',
		'event: token',
		`data: ${JSON.stringify({ text: reply })}`,
		'',
		'event: done',
		`data: ${JSON.stringify({ assistant_message_id: 'season-assistant-msg' })}`,
		'',
	].join('\n');
}

test.describe('/coach season picker', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
	});

	test('My season is offered with a queued plan, survives a reload, and is what the request asks for', async ({
		page,
		mockRoute,
	}) => {
		await rewritePlans(page, mockRoute, true);
		await mockRoute(page, '**/rest/v1/rpc/get_coach_usage*', (route) =>
			route.fulfill({ status: 200, headers: { 'content-type': 'application/json' }, body: '0' }),
		);
		const posts: Array<Record<string, unknown>> = [];
		await mockRoute(page, '**/api/coach', async (route) => {
			posts.push(route.request().postDataJSON() as Record<string, unknown>);
			await route.fulfill({
				status: 200,
				headers: { 'content-type': 'text/event-stream', 'cache-control': 'no-cache' },
				body: sseBody('Your marathon block builds straight into the ultra block.'),
			});
		});

		await page.goto('/coach?plan=none');
		const planTrigger = page.getByRole('button', { name: 'Plan context' });
		await expect(planTrigger).toContainText('No plan', { timeout: 10_000 });

		await planTrigger.click();
		const popover = page.locator('[role="listbox"]');
		await expect(popover).toBeVisible({ timeout: 5_000 });
		const season = popover.getByRole('option', { name: /My season/ });
		await expect(season).toContainText('current plan and the plans queued after it');
		await season.click();
		await expect(popover).toHaveCount(0);
		await expect(page).toHaveURL(/[?&]plan=season\b/);
		await expect(planTrigger).toContainText('My season');

		await page.reload();
		await expect(planTrigger).toContainText('My season', { timeout: 10_000 });

		const composer = page.getByPlaceholder(/Ask about today/);
		await expect(composer).toBeVisible({ timeout: 10_000 });
		await composer.fill('How does my build into the ultra look?');
		await page.locator('form.composer button[type="submit"]').click();
		await expect(page.locator('.bubble', { hasText: 'builds straight into the ultra' })).toBeVisible({
			timeout: 10_000,
		});
		const body = posts[posts.length - 1];
		expect(body.plan_scope).toBe('season');
		// The season's thread is kept under its first plan, the current one.
		expect(body.plan_id).toBe(SEED_PLAN_ID);
	});

	test('with nothing queued after the current plan there is no season option', async ({
		page,
		mockRoute,
	}) => {
		await rewritePlans(page, mockRoute, false);
		await page.goto('/coach?plan=none');
		const planTrigger = page.getByRole('button', { name: 'Plan context' });
		await expect(planTrigger).toContainText('No plan', { timeout: 10_000 });
		await planTrigger.click();
		const popover = page.locator('[role="listbox"]');
		await expect(popover.getByRole('option', { name: /Richmond Half 2026/ })).toBeVisible({ timeout: 5_000 });
		await expect(popover.getByRole('option', { name: /My season/ })).toHaveCount(0);
	});
});
