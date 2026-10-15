import type { Page } from '@playwright/test';

import { browserDate } from '../fixtures/dates';
import type { MockRoute } from '../fixtures/mock-route';
import { expect, test } from '../fixtures/test';
import { USER_A } from '../fixtures/users';

/**
 * /coach → the AI plan assistant handoff (decisions § 1930). The coach never
 * writes a plan; with the assistant live, a new chat offers a plan-building
 * chip, and the coach's reply carries one `/plans/new?describe=…` link that
 * drops the runner on the wizard with the description filled in.
 *
 * The active thread is stubbed empty so the primer renders regardless of what
 * other specs left in USER_A's no-plan thread, and `/coach?plan=none` with
 * USER_A's seeded runs selects the no-plan suggestion set. `/api/coach` and
 * `/api/coach/plan-request` are both stubbed: the prompt that makes the model
 * write the link is unit-tested in `src/lib/coach/system_prompt.test.ts`, and
 * the sanitiser that keeps it in-app in `src/lib/coach/markdown.test.ts`.
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

	async function emptyActiveThread(page: Page, mockRoute: MockRoute) {
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

	test('the coach reply links to the plan builder, which opens in-app with the box filled', async ({
		page,
		mockRoute
	}) => {
		const raceDate = browserDate(84);
		const description = `Half marathon on ${raceDate}, 4 days a week`;
		const href = `/plans/new?describe=${encodeURIComponent(description)}`;
		const reply =
			'I will not write the workouts myself, but the plan builder will. ' +
			`[Build this plan](${href}) fills in the form and the app's generator builds the plan for you to review.`;

		await emptyActiveThread(page, mockRoute);
		await mockRoute(page, '**/rest/v1/rpc/get_coach_usage*', async (route) => {
			await route.fulfill({ status: 200, contentType: 'application/json', body: '0' });
		});
		await mockRoute(page, '**/api/coach', async (route) => {
			await route.fulfill({
				status: 200,
				headers: { 'content-type': 'text/event-stream', 'cache-control': 'no-cache' },
				body: [
					'event: meta',
					`data: ${JSON.stringify({
						user_message_id: 'handoff-user-msg',
						tier: 'free',
						limits: { daily_limit: 10 }
					})}`,
					'',
					'event: token',
					`data: ${JSON.stringify({ text: reply })}`,
					'',
					'event: done',
					`data: ${JSON.stringify({ assistant_message_id: 'handoff-assistant-msg' })}`,
					''
				].join('\n')
			});
		});
		const planRequests: Array<{ request?: string }> = [];
		await mockRoute(page, '**/api/coach/plan-request', async (route) => {
			planRequests.push(route.request().postDataJSON());
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					inputs: {
						goalEvent: 'distance_half',
						raceDate,
						goalTimeSec: null,
						recent5kSec: null,
						daysPerWeek: 4,
						weeks: null,
						beginnerWalkRun: false,
						planName: null,
						assumptions: []
					}
				})
			});
		});

		await page.goto('/coach?plan=none');
		await page.locator('.primer .suggest').first().click({ timeout: 10_000 });
		await page.locator('form.composer button[type="submit"]').click();

		const link = page.locator('.bubble').getByRole('link', { name: 'Build this plan' });
		await expect(link).toBeVisible({ timeout: 10_000 });
		await expect(link).toHaveAttribute('href', href);
		// An anchor with a target is external to SvelteKit's router.
		await expect(link).not.toHaveAttribute('target');

		await link.click();

		const editor = page.locator('form.plan-editor');
		await expect(editor.locator('.ai-applied')).toBeVisible({ timeout: 10_000 });
		await expect(page).toHaveURL(/\/plans\/new(?:\?|$|#)/);
		await expect(page).not.toHaveURL(/describe=/);
		await expect(
			editor.getByRole('textbox', { name: 'Describe the plan you want' })
		).toHaveValue(description);
		await expect(editor.getByRole('combobox', { name: /Goal race/ })).toHaveValue('distance_half');
		expect(planRequests).toHaveLength(1);
		expect(planRequests[0].request).toBe(description);
	});
});
