import { readFileSync } from 'node:fs';

import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { USER_A } from '../fixtures/users';

/// A plan already under way: its start date is behind today and not a Sunday.
const PAST_PLAN_MD = [
	'# Imported mid-block plan',
	'- Goal event: distance_full',
	'- Start date: 2020-01-03',
	'',
	'| Week | Date | Type | Distance | Pace | Notes |',
	'| --- | --- | --- | --- | --- | --- |',
	'| 1 | 2020-01-03 | easy | 5.00 km | | |',
	'| 1 | 2020-01-04 | long | 20.00 km | 6:24 | |',
].join('\n');

/**
 * Plan import / export (roadmap Phase 3 — Sharing & handoff + Import).
 * The Markdown/JSON serialize round-trip is unit-tested; this pins the
 * UI wiring: the export menu on /plans/[id] produces a file, and the
 * paste-import on /plans/new parses a table into the editable preview.
 *
 * The USER_A import tests stop at the preview (don't submit) so they never
 * flip USER_A's seeded active plan to completed — other specs rely on
 * Richmond Half 2026 staying active. The one case that submits runs as a
 * throwaway user.
 */

test.describe('plan import / export', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('export menu downloads a Markdown plan with the workout table', async ({ page }) => {
		await page.goto('/plans');
		await page.getByRole('link', { name: /Richmond Half 2026/ }).click();
		await expect(page.getByRole('heading', { level: 1, name: /Richmond Half 2026/ }))
			.toBeVisible({ timeout: 10_000 });

		// Open the Export disclosure, then trigger the .md download.
		await page.locator('.export-menu summary').click();
		const [download] = await Promise.all([
			page.waitForEvent('download'),
			page.getByRole('menuitem', { name: /Download \.md/ }).click(),
		]);
		const path = await download.path();
		const content = readFileSync(path, 'utf-8');
		expect(content).toMatch(/^# Richmond Half 2026/m);
		expect(content).toMatch(/\| Week \| Date \| Type \| Distance \| Pace \| Notes \|/);
		// At least one data row (a date cell).
		expect(content).toMatch(/\|\s*1\s*\|\s*\d{4}-\d{2}-\d{2}\s*\|/);
	});

	test('export menu supports arrow-key / Home / End navigation and Escape', async ({ page }) => {
		await page.goto('/plans');
		await page.getByRole('link', { name: /Richmond Half 2026/ }).click();
		await expect(page.getByRole('heading', { level: 1, name: /Richmond Half 2026/ }))
			.toBeVisible({ timeout: 10_000 });

		const copy = page.getByRole('menuitem', { name: 'Copy as Markdown' });
		const md = page.getByRole('menuitem', { name: 'Download .md' });
		const json = page.getByRole('menuitem', { name: 'Download .json' });

		// Opening moves focus into the menu (first item).
		await page.locator('.export-menu summary').click();
		await expect(copy).toBeFocused();

		// ArrowDown walks forward and wraps.
		await page.keyboard.press('ArrowDown');
		await expect(md).toBeFocused();
		await page.keyboard.press('ArrowDown');
		await expect(json).toBeFocused();
		await page.keyboard.press('ArrowDown');
		await expect(copy).toBeFocused();

		// ArrowUp walks backward and wraps.
		await page.keyboard.press('ArrowUp');
		await expect(json).toBeFocused();

		// Home / End jump to first / last.
		await page.keyboard.press('Home');
		await expect(copy).toBeFocused();
		await page.keyboard.press('End');
		await expect(json).toBeFocused();

		// Escape closes the menu and returns focus to the trigger.
		await page.keyboard.press('Escape');
		await expect(copy).toBeHidden();
		await expect(page.locator('.export-menu summary')).toBeFocused();
	});

	test('paste-import parses a Markdown table into the editable preview', async ({ page }) => {
		await page.goto('/plans/new');
		// The generator shows a default (half-marathon) outline first.
		await expect(page.locator('.week-item').first()).toBeVisible({ timeout: 10_000 });

		const md = [
			'# Imported e2e plan',
			'- Goal event: distance_10k',
			'- Start date: 2026-08-02',
			'',
			'| Week | Date | Type | Distance | Pace | Notes |',
			'| --- | --- | --- | --- | --- | --- |',
			'| 1 | 2026-08-02 | long | 14.00 km | 6:00 | base |',
			'| 1 | 2026-08-04 | easy | 8.00 km | 6:30 | |',
			'| 2 | 2026-08-09 | long | 16.00 km | 6:00 | |',
		].join('\n');

		await page.getByText('Import a plan', { exact: true }).click();
		await page.locator('.import-text').fill(md);
		await page.getByRole('button', { name: 'Load plan' }).click();

		// Import mode note appears and the preview collapses to the 2
		// imported weeks (vs the generator's ~12-week default).
		await expect(page.locator('.imported-note')).toBeVisible();
		await expect(page.locator('.week-item')).toHaveCount(2);
		// Name field picked up the parsed title.
		await expect(page.locator('input[type="text"]').first()).toHaveValue('Imported e2e plan');
	});

	test('an imported plan that started in the past still passes form validation', async ({ page }) => {
		await page.goto('/plans/new');
		await expect(page.locator('.week-item').first()).toBeVisible({ timeout: 10_000 });

		// The generator's min=today on the date input used to make the browser
		// refuse to submit an imported plan that had already started, though
		// submit() lets imports through. The generator itself keeps it.
		// /plans/new also renders the starter and club-template pickers, each
		// with its own date input; the editor's is the one its hint describes.
		const startInput = page.locator('input[type="date"][aria-describedby="start-date-hint"]');
		await expect(startInput).toHaveAttribute('min', browserDate(0));

		await page.getByText('Import a plan', { exact: true }).click();
		await page.getByRole('textbox', { name: 'Import a plan' }).fill(PAST_PLAN_MD);
		await page.getByRole('button', { name: 'Load plan' }).click();
		await expect(page.locator('.imported-note')).toBeVisible();

		await expect(startInput).toHaveValue('2020-01-03');
		await expect(startInput).not.toHaveAttribute('min');
		expect(await startInput.evaluate((el: HTMLInputElement) => el.checkValidity())).toBe(true);

		// Picking a date by hand hands the plan back to the generator, and the
		// generator's floor comes back with it.
		await startInput.fill(browserDate(14));
		await expect(page.locator('.imported-note')).toHaveCount(0);
		await expect(startInput).toHaveAttribute('min', browserDate(0));
	});

	test('an imported ultra plan with a goal over nine hours passes form validation', async ({ page }) => {
		await page.goto('/plans/new');
		await expect(page.locator('.week-item').first()).toBeVisible({ timeout: 10_000 });

		// The hours box was capped at 9, so the browser refused to submit a
		// Comrades-length goal that the import itself had parsed correctly.
		const md = [
			'# Imported ultra plan',
			'- Goal event: custom',
			'- Goal distance: 91 km',
			'- Goal time: 11:00:00',
			'- Start date: 2020-01-03',
			'',
			'| Week | Date | Type | Distance | Pace | Notes |',
			'| --- | --- | --- | --- | --- | --- |',
			'| 1 | 2020-01-03 | easy | 5.00 km | | |',
		].join('\n');
		await page.getByText('Import a plan', { exact: true }).click();
		await page.getByRole('textbox', { name: 'Import a plan' }).fill(md);
		await page.getByRole('button', { name: 'Load plan' }).click();
		await expect(page.locator('.imported-note')).toBeVisible();

		const hours = page.locator('input[type="number"][aria-describedby="goal-time-hint"]').first();
		await expect(hours).toHaveValue('11');
		expect(await hours.evaluate((el: HTMLInputElement) => el.checkValidity())).toBe(true);
	});

	test('the import box spans the editor rather than the narrow form column', async ({ page }) => {
		await page.goto('/plans/new');
		await expect(page.locator('.week-item').first()).toBeVisible({ timeout: 10_000 });
		await page.getByText('Import a plan', { exact: true }).click();

		const textbox = page.getByRole('textbox', { name: 'Import a plan' });
		const box = await textbox.boundingBox();
		const formColumn = await page.locator('.plan-editor .form').boundingBox();
		expect(box).not.toBeNull();
		expect(formColumn).not.toBeNull();
		expect(box!.width).toBeGreaterThan(formColumn!.width);

		// A row wider than the box scrolls sideways instead of wrapping, so
		// every pasted table row stays on one line.
		const wideRow = `| 1 | 2020-01-04 | long | 20.00 km | 6:24 | ${'steady over the rolling section, '.repeat(6)}|`;
		await textbox.fill(wideRow);
		expect(
			await textbox.evaluate((el: HTMLTextAreaElement) => el.scrollWidth > el.clientWidth),
		).toBe(true);
	});
});

// Runs as a throwaway user, so creating the plan touches no seeded plan the
// other specs read.
test.describe('plan import — create', () => {
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[] = [];

	test.beforeAll(async () => {
		users = await createSagaUsers(1, { displayNames: [`Plan Import ${Date.now().toString(36)}`] });
	});

	test.afterAll(async () => {
		await deleteSagaUsers(users);
	});

	// submit() refuses a past start and snaps a non-Sunday one for a generated
	// plan; an import has to come through with the dates it was pasted with.
	test('an imported plan that started in the past is created on its own start date', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: users[0].storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto('/plans/new');
			await expect(page.locator('.week-item').first()).toBeVisible({ timeout: 10_000 });
			await page.getByText('Import a plan', { exact: true }).click();
			await page.getByRole('textbox', { name: 'Import a plan' }).fill(PAST_PLAN_MD);
			await page.getByRole('button', { name: 'Load plan' }).click();
			await expect(page.locator('.imported-note')).toBeVisible();

			await page.getByRole('button', { name: 'Create plan' }).click();
			await page.waitForURL(/\/plans\/[0-9a-f-]{36}$/, { timeout: 15_000 });
			const planId = page.url().split('/').pop()!;

			const { data: plan, error } = await getAdminClient()
				.from('training_plans')
				.select('start_date, plan_weeks(plan_workouts(scheduled_date))')
				.eq('id', planId)
				.single();
			if (error) throw error;
			expect(plan.start_date).toBe('2020-01-03');
			const dates = plan.plan_weeks
				.flatMap((w) => w.plan_workouts.map((wo) => wo.scheduled_date))
				.sort();
			expect(dates).toEqual(['2020-01-03', '2020-01-04']);
		} finally {
			await ctx.close();
		}
	});
});
