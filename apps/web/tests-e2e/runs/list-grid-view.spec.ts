import type { Browser, Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { browserDayAt } from '../fixtures/dates';
import { acceptCookieConsent, switchRunsToAllTime } from '../fixtures/helpers';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * /runs list + grid views (decisions § 2117).
 *
 * The runner here logs runs and nothing else — the person History used to
 * duplicate /runs for. Two runs today and one two days ago give the list view
 * two day groups to head. The History nav gate for the same runner is
 * history/nav-gate.spec.ts.
 */
test.describe.configure({ mode: 'serial' });

test.describe('/runs list and grid views', () => {
	let runner: SagaUser;
	const runIds: string[] = [];

	test.beforeAll(async () => {
		[runner] = await createSagaUsers(1, { displayNames: ['Runs View Saga'] });
		runIds.push(
			await insertRun({ user_id: runner.id, started_at: browserDayAt(0, 9), duration_s: 1500, distance_m: 5000 }),
			await insertRun({ user_id: runner.id, started_at: browserDayAt(0, 7), duration_s: 1200, distance_m: 4000 }),
			await insertRun({ user_id: runner.id, started_at: browserDayAt(-2, 8), duration_s: 3000, distance_m: 10000 }),
		);
	});

	test.afterAll(async () => {
		if (runner) await deleteSagaUsers([runner]).catch(() => {});
	});

	async function openPage(browser: Browser, user: SagaUser): Promise<Page> {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		return ctx.newPage();
	}

	test('the toggle switches views, and the choice survives a reload and a bare /runs', async ({
		browser,
	}) => {
		const page = await openPage(browser, runner);
		try {
			await page.goto('/runs');
			await switchRunsToAllTime(page);
			await expect(page.getByTestId('runs-grid-view')).toBeVisible({ timeout: 15_000 });
			await expect(page.locator('.run-card')).toHaveCount(3);

			const list = page.getByTestId('runs-view-list');
			await list.click();
			await expect(list).toHaveAttribute('aria-pressed', 'true');
			await expect(page.getByTestId('runs-list-view')).toBeVisible();
			await expect(page.locator('.run-card')).toHaveCount(0);
			await expect(page).toHaveURL(/\/runs\?(.*&)?view=list/);

			await page.reload();
			await expect(page.getByTestId('runs-list-view')).toBeVisible({ timeout: 15_000 });

			// No ?view= in the link: the remembered choice applies.
			await page.goto('/runs');
			await expect(page.getByTestId('runs-list-view')).toBeVisible({ timeout: 15_000 });

			await page.getByTestId('runs-view-grid').click();
			await expect(page.getByTestId('runs-grid-view')).toBeVisible();
			await expect(page).toHaveURL(/\/runs\?(.*&)?view=grid/);
			await page.goto('/runs');
			await expect(page.getByTestId('runs-grid-view')).toBeVisible({ timeout: 15_000 });
		} finally {
			await page.context().close();
		}
	});

	test('?view=list opens the list view with nothing remembered', async ({ browser }) => {
		const page = await openPage(browser, runner);
		try {
			await page.goto('/runs?view=list');
			await expect(page.getByTestId('runs-list-view')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('runs-view-list')).toHaveAttribute('aria-pressed', 'true');
		} finally {
			await page.context().close();
		}
	});

	test('the list view heads each day and a row opens its run', async ({ browser }) => {
		const page = await openPage(browser, runner);
		try {
			await page.goto('/runs?view=list');
			await switchRunsToAllTime(page);
			const groups = page.getByTestId('timeline-day-group');
			await expect(groups).toHaveCount(2, { timeout: 15_000 });
			await expect(groups.nth(0).locator('.timeline-day')).toHaveText('Today');
			await expect(groups.nth(0).locator('.timeline-row')).toHaveCount(2);
			await expect(groups.nth(1).locator('.timeline-row')).toHaveCount(1);

			// Newest first: the 09:00 run heads today.
			await groups.nth(0).locator('.timeline-row').first().click();
			await expect(page).toHaveURL(new RegExp(`/runs/${runIds[0]}`));
		} finally {
			await page.context().close();
		}
	});

	test('a distance sort drops the day headings for one list in that order', async ({ browser }) => {
		const page = await openPage(browser, runner);
		try {
			await page.goto('/runs?view=list');
			await switchRunsToAllTime(page);
			await page.getByLabel('Sort', { exact: true }).selectOption('longest');
			await expect(page.getByTestId('timeline-day-group')).toHaveCount(1, { timeout: 15_000 });
			await expect(page.locator('.timeline-day')).toHaveCount(0);
			await expect(page.locator('.timeline-row').first()).toHaveAttribute(
				'href',
				`/runs/${runIds[2]}`,
			);
		} finally {
			await page.context().close();
		}
	});

	test('Select works in the list view: a row toggles instead of navigating', async ({ browser }) => {
		const page = await openPage(browser, runner);
		try {
			await page.goto('/runs?view=list');
			await switchRunsToAllTime(page);
			await expect(page.locator('.timeline-row')).toHaveCount(3, { timeout: 15_000 });
			await page.getByRole('button', { name: 'Select', exact: true }).click();
			const row = page.locator('button.timeline-row').first();
			await row.click();
			await expect(row).toHaveAttribute('aria-pressed', 'true');
			await expect(page).toHaveURL(/\/runs\?/);
			await expect(page.getByText('1 selected')).toBeVisible();
		} finally {
			await page.context().close();
		}
	});
});
