import type { Browser, Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { browserDayAt } from '../fixtures/dates';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * The History nav item is data-gated (decisions § 2114).
 *
 * For a runner who logs runs and nothing else, History repeated /runs in a
 * plainer form, so the sidebar hides it and a direct visit lands on the run
 * list's day view. A runner with one gym workout keeps the cross-modal
 * timeline unchanged. Both are clean saga users so the gate reads only what
 * each spec planted.
 */
test.describe.configure({ mode: 'serial' });

test.describe('History nav gate', () => {
	let runner: SagaUser;
	let lifter: SagaUser;

	test.beforeAll(async () => {
		[runner, lifter] = await createSagaUsers(2, {
			displayNames: ['History Gate Runner', 'History Gate Lifter'],
		});
		await insertRun({ user_id: runner.id, started_at: browserDayAt(-1, 8), duration_s: 1500, distance_m: 5000 });
		await insertRun({ user_id: lifter.id, started_at: browserDayAt(-1, 8), duration_s: 1800, distance_m: 6000 });
		const { error } = await getAdminClient()
			.from('gym_workouts')
			.insert({
				user_id: lifter.id,
				title: 'History Gate Lift',
				started_at: browserDayAt(-1, 18),
				last_modified_at: browserDayAt(-1, 18),
			});
		expect(error).toBeNull();
	});

	test.afterAll(async () => {
		const users = [runner, lifter].filter(Boolean);
		if (users.length > 0) await deleteSagaUsers(users).catch(() => {});
	});

	async function openPage(browser: Browser, user: SagaUser): Promise<Page> {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		return ctx.newPage();
	}

	// The gate is the two one-row presence reads; absence only means something
	// once both have answered.
	function presenceReads(page: Page) {
		const presence = (table: string) => (r: { url(): string }) => {
			const url = r.url();
			return url.includes(`/rest/v1/${table}?`) && url.includes('select=id&') && url.includes('limit=1');
		};
		return Promise.all([
			page.waitForResponse(presence('gym_workouts')),
			page.waitForResponse(presence('food_log')),
		]);
	}

	function navLabel(page: Page, label: string) {
		return page.locator('nav.sidebar .nav-label', { hasText: new RegExp(`^${label}$`) });
	}

	test('a runner with runs only has no History item, and /history lands on the run list', async ({
		browser,
	}) => {
		const page = await openPage(browser, runner);
		try {
			const reads = presenceReads(page);
			await page.goto('/dashboard');
			await reads;
			await expect(navLabel(page, 'Runs')).toBeVisible({ timeout: 15_000 });
			await expect(navLabel(page, 'History')).toHaveCount(0);

			await page.goto('/history');
			await expect(page).toHaveURL(/\/runs\?view=list$/, { timeout: 15_000 });
			await expect(page.getByTestId('runs-list-view')).toBeVisible();
		} finally {
			await page.context().close();
		}
	});

	test('a runner who also lifts keeps History and its timeline', async ({ browser }) => {
		const page = await openPage(browser, lifter);
		try {
			await page.goto('/dashboard');
			await expect(navLabel(page, 'History')).toBeVisible({ timeout: 15_000 });

			await page.goto('/history');
			await expect(page.getByRole('button', { name: 'Lifts', exact: true })).toBeVisible({
				timeout: 15_000,
			});
			await expect(page.locator('.timeline-row', { hasText: 'History Gate Lift' })).toBeVisible();
			await expect(page).toHaveURL(/\/history$/);
		} finally {
			await page.context().close();
		}
	});
});
