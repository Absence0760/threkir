import type { Browser, Locator, Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun } from '../fixtures/simulate';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { USER_A } from '../fixtures/users';

/**
 * /plans wizard — the first question and what follows from it (issue #1186):
 * a runner who has never run gets the walk-run plan with no race fields and
 * can start tomorrow; a runner building up picks a distance but no goal
 * time; a runner back from a break gets an eased-in opening week; and a goal
 * faster than recent runs support is called out.
 *
 * Only the two-day walk-run case creates a plan, on a saga user with no other
 * plan to overlap. The break and goal cases run on saga users too, whose
 * history is exactly what the test plants.
 */

const DAY_MS = 24 * 3600 * 1000;

function isoDaysFromToday(days: number): string {
	const d = new Date();
	d.setDate(d.getDate() + days);
	const m = String(d.getMonth() + 1).padStart(2, '0');
	const day = String(d.getDate()).padStart(2, '0');
	return `${d.getFullYear()}-${m}-${day}`;
}

/// A wizard fieldset by its legend. The starting-point hints mention a goal
/// time too, so matching on any text inside would find that fieldset.
function fieldsetByLegend(scope: Locator, legend: RegExp) {
	return scope.locator('fieldset').filter({ has: scope.page().locator('legend', { hasText: legend }) });
}

async function openWizard(page: Page) {
	await page.goto('/plans');
	await page.getByRole('button', { name: /New plan/ }).first().click();
	const modal = page.locator('.modal');
	await expect(modal).toBeVisible({ timeout: 5_000 });
	return modal;
}

async function openAs(browser: Browser, baseURL: string | undefined, user: SagaUser) {
	const context = await browser.newContext({ baseURL, storageState: user.storageStatePath });
	const page = await context.newPage();
	return { context, modal: await openWizard(page) };
}

test.describe('/plans wizard — where are you starting from', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('"I\'ve never run" is a walk-run plan with no race fields that can start tomorrow', async ({
		page
	}) => {
		const modal = await openWizard(page);
		const startingPoint = modal.getByRole('group', { name: 'Where are you starting from?' });
		await expect(startingPoint.getByRole('radio', { name: /I'm training for a race/ })).toBeChecked();

		await startingPoint.getByRole('radio', { name: /I've never run/ }).check();

		await expect(modal.getByLabel('Goal race')).toHaveCount(0);
		await expect(fieldsetByLegend(modal, /^Goal time/)).toHaveCount(0);
		await expect(fieldsetByLegend(modal, /^Recent 5K time/)).toHaveCount(0);
		await expect(modal.getByLabel('Days per week').locator('option')).toHaveText([
			'2 days',
			'3 days'
		]);
		await expect(modal.locator('input[type="date"]').first()).toHaveValue(isoDaysFromToday(1));
		await expect(modal.getByText('A walk-run plan can start on any day, today included.')).toBeVisible();

		// Today is a valid start, whatever weekday it is.
		await modal.locator('input[type="date"]').first().fill(isoDaysFromToday(0));
		await modal.locator('input[type="date"]').first().dispatchEvent('change');
		await expect(modal.locator('input[type="date"]').first()).toHaveValue(isoDaysFromToday(0));
		await expect(modal.getByText('Moved to the next Sunday')).toHaveCount(0);
	});

	test('"I run a bit" picks a distance but asks for no goal time', async ({ page }) => {
		const modal = await openWizard(page);
		await modal
			.getByRole('group', { name: 'Where are you starting from?' })
			.getByRole('radio', { name: /I run a bit/ })
			.check();

		await expect(modal.getByLabel('Goal race')).toBeVisible();
		await expect(fieldsetByLegend(modal, /^Goal time/)).toHaveCount(0);
		await expect(modal.getByLabel('Days per week').locator('option')).toHaveCount(5);
	});
});

test.describe('/plans wizard — a two-day walk-run plan saves', () => {
	let users: SagaUser[] = [];

	test.beforeAll(async () => {
		users = await createSagaUsers(1, { displayNames: ['Saga Two Day Walker'] });
	});

	test.afterAll(async () => {
		if (users.length > 0) await deleteSagaUsers(users);
	});

	test('"I\'ve never run" on 2 days a week creates the plan', async ({ browser, baseURL }) => {
		const { context, modal } = await openAs(browser, baseURL, users[0]);
		try {
			const page = modal.page();
			await modal
				.getByRole('group', { name: 'Where are you starting from?' })
				.getByRole('radio', { name: /I've never run/ })
				.check();
			await modal.getByPlaceholder('Autumn half marathon').fill('Two-day walk-run');
			await modal.getByLabel('Days per week').selectOption('2');
			const submit = modal.getByRole('button', { name: /Create plan/ });
			await expect(submit).toBeEnabled({ timeout: 10_000 });
			await submit.click();
			await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
			const planId = page.url().split('/').pop()!;

			const { data, error } = await getAdminClient()
				.from('training_plans')
				.select('days_per_week')
				.eq('id', planId)
				.single();
			expect(error).toBeNull();
			expect(data?.days_per_week).toBe(2);
		} finally {
			await context.close();
		}
	});
});

test.describe('/plans wizard — a runner back from a break', () => {
	let users: SagaUser[] = [];

	test.beforeAll(async () => {
		users = await createSagaUsers(1, { displayNames: ['Saga Comeback Runner'] });
		// Four 40 km weeks that ended 60 days ago, and nothing since.
		for (const daysAgo of [60, 67, 74, 81]) {
			await insertRun({
				user_id: users[0].id,
				started_at: new Date(Date.now() - daysAgo * DAY_MS).toISOString(),
				duration_s: 4 * 3600,
				distance_m: 40_000
			});
		}
	});

	test.afterAll(async () => {
		if (users.length > 0) await deleteSagaUsers(users);
	});

	test('the opening week is capped at half the pre-break average unless turned off', async ({
		browser,
		baseURL
	}) => {
		const { context, modal } = await openAs(browser, baseURL, users[0]);
		try {
			await modal.getByLabel('Goal race').selectOption('distance_full');
			const note = modal.getByTestId('plan-return-note');
			await expect(note).toBeVisible({ timeout: 10_000 });
			await expect(note).toContainText('Coming back from a break');
			await expect(note).toContainText('about 9 weeks off');
			await expect(note).toContainText('no more than 20 km');

			const weekOne = modal.locator('.week-km').first();
			const km = async () => Number((await weekOne.innerText()).match(/[\d.]+/)?.[0]);
			await expect.poll(km).toBeLessThanOrEqual(20);

			await note.getByRole('checkbox', { name: 'Ease me back in' }).uncheck();
			await expect.poll(km).toBeGreaterThan(20);

			await note.getByRole('button', { name: 'Return with walk-run intervals instead' }).click();
			await expect(modal.getByRole('checkbox', { name: /New to running/i })).toBeChecked();
		} finally {
			await context.close();
		}
	});
});

test.describe('/plans wizard — a goal ahead of recent runs', () => {
	let users: SagaUser[] = [];

	test.beforeAll(async () => {
		users = await createSagaUsers(1, { displayNames: ['Saga Goal Runner'] });
		// A steady 5 km in 30:00 twice a week for three weeks: about 62 minutes
		// for 10K, with enough recent efforts for a confident projection.
		for (const daysAgo of [2, 5, 9, 12, 16, 19]) {
			await insertRun({
				user_id: users[0].id,
				started_at: new Date(Date.now() - daysAgo * DAY_MS).toISOString(),
				duration_s: 1800,
				distance_m: 5_000
			});
		}
	});

	test.afterAll(async () => {
		if (users.length > 0) await deleteSagaUsers(users);
	});

	test('a 10K goal of 40 minutes is called out; a realistic one is not', async ({
		browser,
		baseURL
	}) => {
		const { context, modal } = await openAs(browser, baseURL, users[0]);
		try {
			await modal.getByLabel('Goal race').selectOption('distance_10k');
			const goalTime = fieldsetByLegend(modal, /^Goal time/).locator('input');
			await goalTime.nth(0).fill('0');
			await goalTime.nth(1).fill('40');
			await goalTime.nth(2).fill('0');
			const warning = modal.getByTestId('plan-goal-ahead');
			await expect(warning).toBeVisible({ timeout: 10_000 });
			await expect(warning).toContainText('quicker than your recent runs suggest');

			await goalTime.nth(1).fill('62');
			await expect(warning).toHaveCount(0);
		} finally {
			await context.close();
		}
	});
});

test.describe('/plans/new — the starter picker', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('Couch to 5K says what it asks and starts tomorrow', async ({ page }) => {
		await page.goto('/plans/new');
		const picker = page.locator('.starter-picker');
		await picker.getByLabel('Starter plan').selectOption('c25k');
		await expect(page.getByTestId('starter-summary')).toHaveText(
			/^9 weeks · 3 days a week · \d+–\d+ min a session$/
		);
		await expect(picker.locator('input[type="date"]')).toHaveValue(isoDaysFromToday(1));

		await picker.getByLabel('Starter plan').selectOption('half_12wk');
		await expect(page.getByTestId('starter-summary')).toHaveText('12 weeks · 4 days a week');
		const start = await picker.locator('input[type="date"]').inputValue();
		expect(new Date(`${start}T00:00:00`).getDay()).toBe(0);
	});
});
