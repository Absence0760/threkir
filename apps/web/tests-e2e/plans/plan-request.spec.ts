import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { USER_A } from '../fixtures/users';

/**
 * /plans/new — the "Describe the plan you want" box (AI plan assistant).
 *
 * `/api/coach/plan-request` is mocked at the network layer, so no Anthropic
 * key is needed: the endpoint's own gates (consent, the daily cap, the
 * forced-tool call, the refund) are unit-tested in
 * `src/lib/training/plan_request/handler.test.ts` and the clamp boundary in
 * `inputs.test.ts`. Here we pin the wizard wiring: a success fills the form
 * fields (never the recent-5K confirmation), a consent refusal points at
 * /coach, and a failure leaves the manual form generating as before. No plan
 * is created, so there is no server state to clean up.
 */
test.describe('/plans/new — AI plan request', () => {
	test.use({ storageState: USER_A.storageStatePath });

	async function describe(page: import('@playwright/test').Page, text: string) {
		await page.goto('/plans/new');
		const editor = page.locator('form.plan-editor');
		await editor.getByRole('textbox', { name: 'Describe the plan you want' }).fill(text);
		await editor.getByRole('button', { name: 'Fill in the form' }).click();
		return editor;
	}

	test('a successful extraction fills the form, explains itself, and leaves the 5K unconfirmed', async ({
		page,
		mockRoute
	}) => {
		const raceDate = browserDate(70);
		const seen: { body: { request?: string; today?: string } | null } = { body: null };
		await mockRoute(page, '**/api/coach/plan-request', async (route) => {
			seen.body = route.request().postDataJSON();
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					inputs: {
						goalEvent: 'distance_10k',
						raceDate,
						goalTimeSec: 2940,
						recent5kSec: 1590,
						daysPerWeek: 5,
						weeks: null,
						beginnerWalkRun: false,
						planName: 'Spring 10K',
						assumptions: ['days_per_week_clamped']
					}
				})
			});
		});

		const editor = await describe(page, 'a 49 minute 10k in ten weeks, 5 days a week, last 5k 26:30');

		const status = editor.locator('.ai-applied');
		await expect(status).toBeVisible({ timeout: 10_000 });
		await expect(status).toContainText('not by the AI');
		await expect(status).toContainText('race week includes');
		await expect(status).toContainText('nearest the planner supports');

		expect(seen.body?.today).toBe(browserDate(0));

		await expect(editor.getByRole('combobox', { name: /Goal race/ })).toHaveValue('distance_10k');
		await expect(editor.getByRole('combobox', { name: /Days per week/ })).toHaveValue('5');
		await expect(editor.getByRole('textbox', { name: /Plan name/ })).toHaveValue('Spring 10K');

		const recent = editor.locator('fieldset', { hasText: 'Recent 5K time' });
		await expect(recent.locator('input[type="number"]').nth(0)).toHaveValue('26');
		await expect(recent.locator('input[type="number"]').nth(1)).toHaveValue('30');
		// The runner still has to vouch for the time — the AI never does.
		await expect(editor.getByRole('checkbox', { name: /current fitness/i })).not.toBeChecked();

		// The generator built a preview from the filled fields.
		await expect(editor.locator('.weeks .week-item').first()).toBeVisible();
		await expect(editor.getByRole('button', { name: 'Create plan' })).toBeEnabled();
	});

	test('a second fill replaces the first one\'s length and goal time rather than inheriting them', async ({
		page,
		mockRoute
	}) => {
		const replies = [
			{ goalEvent: 'distance_half', goalTimeSec: 6900, weeks: 12 },
			{ goalEvent: 'distance_10k', goalTimeSec: null, weeks: null }
		];
		await mockRoute(page, '**/api/coach/plan-request', async (route) => {
			const next = replies.shift()!;
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					inputs: {
						...next,
						raceDate: null,
						recent5kSec: null,
						daysPerWeek: 4,
						beginnerWalkRun: false,
						planName: null,
						assumptions: []
					}
				})
			});
		});

		const editor = await describe(page, 'a 1:55 half in twelve weeks');
		await expect(editor.locator('.ai-applied')).toBeVisible({ timeout: 10_000 });
		const weeksInput = editor.locator('input[type="number"][min="4"][max="24"]');
		const goalTime = editor.locator('fieldset', { hasText: 'Goal time' }).first().locator('input[type="number"]');
		await expect(weeksInput).toHaveValue('12');
		await expect(goalTime.nth(0)).toHaveValue('1');

		await editor.getByRole('textbox', { name: 'Describe the plan you want' }).fill('actually just a 10k');
		await editor.getByRole('button', { name: 'Fill in the form' }).click();
		await expect(editor.getByRole('combobox', { name: /Goal race/ })).toHaveValue('distance_10k', {
			timeout: 10_000
		});
		await expect(weeksInput).toHaveValue('');
		await expect(goalTime.nth(0)).toHaveValue('');
	});

	test('a ?describe= deep link fills once on arrival and then leaves the URL', async ({
		page,
		mockRoute
	}) => {
		// The coach's plan handoff lands here. The fill spends a Coach
		// message, so it must run exactly once and the param must be gone
		// before a reload could run it again.
		const bodies: Array<{ request?: string }> = [];
		await mockRoute(page, '**/api/coach/plan-request', async (route) => {
			bodies.push(route.request().postDataJSON());
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					inputs: {
						goalEvent: 'distance_half',
						raceDate: null,
						goalTimeSec: null,
						recent5kSec: null,
						daysPerWeek: 4,
						weeks: 12,
						beginnerWalkRun: false,
						planName: null,
						assumptions: []
					}
				})
			});
		});

		const description = 'A half marathon in twelve weeks, 4 days a week';
		await page.goto(`/plans/new?describe=${encodeURIComponent(description)}`);

		const editor = page.locator('form.plan-editor');
		await expect(editor.locator('.ai-applied')).toBeVisible({ timeout: 10_000 });
		const box = editor.getByRole('textbox', { name: 'Describe the plan you want' });
		await expect(box).toHaveValue(description);
		await expect(editor.getByRole('combobox', { name: /Goal race/ })).toHaveValue('distance_half');
		await expect(editor.getByRole('combobox', { name: /Days per week/ })).toHaveValue('4');

		// A describe link is a training-plan request: no kind chooser.
		await expect(page.getByTestId('kind-training')).toHaveCount(0);

		await expect(page).not.toHaveURL(/describe=/);
		expect(bodies).toHaveLength(1);
		expect(bodies[0].request).toBe(description);

		await page.reload();
		await expect(box).toBeVisible({ timeout: 10_000 });
		await expect(box).toHaveValue('');
		await expect(editor.locator('.ai-applied')).toHaveCount(0);
		expect(bodies).toHaveLength(1);
	});

	test('a consent refusal links to /coach to accept the updated disclosure', async ({ page, mockRoute }) => {
		await mockRoute(page, '**/api/coach/plan-request', async (route) => {
			await route.fulfill({
				status: 403,
				contentType: 'application/json',
				body: JSON.stringify({
					error: 'ai disclosure required',
					code: 'ai_disclosure_required',
					required_version: 3
				})
			});
		});

		const editor = await describe(page, 'a marathon in the spring');

		const error = editor.locator('.ai-error');
		await expect(error).toBeVisible({ timeout: 10_000 });
		await expect(error).toContainText('updated AI disclosure');
		await expect(error.getByRole('link')).toHaveAttribute('href', '/coach');
		await expect(editor.locator('.ai-applied')).toHaveCount(0);
	});

	test('a 503 shows the fallback and the manual form still generates', async ({ page, mockRoute }) => {
		await mockRoute(page, '**/api/coach/plan-request', async (route) => {
			await route.fulfill({
				status: 503,
				contentType: 'application/json',
				body: JSON.stringify({ error: 'plan assistant unavailable' })
			});
		});

		const editor = await describe(page, 'a half marathon please');

		await expect(editor.locator('.ai-error')).toContainText('fill in the form yourself', {
			timeout: 10_000
		});
		await expect(editor.locator('.ai-applied')).toHaveCount(0);

		await editor.getByRole('textbox', { name: /Plan name/ }).fill('Manual half');
		await editor.getByRole('combobox', { name: /Goal race/ }).selectOption('distance_half');
		await expect(editor.locator('.weeks .week-item').first()).toBeVisible();
		await expect(editor.getByRole('button', { name: 'Create plan' })).toBeEnabled();
	});
});
