import type { Locator, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * /plans/season — the season planner (issue #1181). The assembler is
 * unit-tested on both platforms (`season_plan.test.ts` ↔
 * `season_plan_test.dart`) and the create loop in `season_create.test.ts`;
 * this pins the page wiring: races entered by hand, confirmed, previewed, and
 * created as chained plans through `create_training_plan`, with the B race
 * written as a race workout in the plan whose window holds it. The other
 * cases stub `/api/coach/season-request`: unavailable (manual entry), races
 * with assumptions (the list fills, each assumption gets its own line, and a
 * 56 km + 90 km season previews as two chained plans), and a 200 with no
 * races (the assumption explains why, manual entry follows).
 *
 * Runs as a throwaway user so the two created active plans overlap nothing.
 */

let users: SagaUser[] = [];

test.beforeAll(async () => {
	users = await createSagaUsers(1, { displayNames: ['Season Runner'] });
});

test.afterAll(async () => {
	await deleteSagaUsers(users);
});

async function fillRace(
	race: Locator,
	r: { name: string; date: string; km: string; priority: 'A' | 'B' | 'C'; goal?: [string, string, string] }
) {
	await race.getByLabel('Name', { exact: true }).fill(r.name);
	await race.getByLabel('Date', { exact: true }).fill(r.date);
	await race.getByLabel('Distance (km)').fill(r.km);
	await race.getByRole('combobox', { name: 'Priority' }).selectOption(r.priority);
	if (r.goal) {
		await race.getByLabel('Goal hours').fill(r.goal[0]);
		await race.getByLabel('Goal minutes').fill(r.goal[1]);
		await race.getByLabel('Goal seconds').fill(r.goal[2]);
	}
}

async function open(page: Page) {
	await page.goto('/plans/season');
	await expect(page.getByRole('heading', { level: 1, name: 'Plan a season' })).toBeVisible({ timeout: 10_000 });
}

test('races entered by hand become two chained plans with the B race inside the second', async ({ browser }) => {
	test.setTimeout(90_000);
	const [runner] = users;
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await context.newPage();
	const first = { name: 'Autumn 10K e2e', date: browserDate(63) };
	const tuneUp = { name: 'Tune-up 10K e2e', date: browserDate(112) };
	const second = { name: 'Spring Half e2e', date: browserDate(140) };
	try {
		await page.goto('/plans/new');
		await page.getByTestId('season-entry').getByRole('link', { name: 'Plan a season' }).click();
		await expect(page).toHaveURL(/\/plans\/season$/);
		await expect(page.getByRole('heading', { level: 1, name: 'Plan a season' })).toBeVisible({ timeout: 10_000 });

		const add = page.getByRole('button', { name: 'Add a race' });
		await add.click();
		await add.click();
		await add.click();
		const races = page.getByTestId('season-race');
		await expect(races).toHaveCount(3);
		await fillRace(races.nth(0), { ...first, km: '10', priority: 'A', goal: ['0', '48', '00'] });
		await fillRace(races.nth(1), { ...tuneUp, km: '10', priority: 'B' });
		await fillRace(races.nth(2), { ...second, km: '21.0975', priority: 'A' });

		await page.getByRole('button', { name: 'Confirm races and preview plans' }).click();
		const preview = page.getByTestId('season-preview');
		await expect(preview.getByTestId('season-plan')).toHaveCount(2);
		await expect(preview.getByTestId('season-plan').nth(0)).toContainText(first.name);
		await expect(preview.getByTestId('season-plan').nth(1)).toContainText(second.name);
		await expect(preview.getByTestId('season-plan').nth(1)).toContainText(tuneUp.name);
		await expect(preview).toContainText(`Recovery after ${first.name}`);
		await expect(preview.getByTestId('season-unplaced')).toHaveCount(0);

		// Editing a race after the preview hides it: nothing is created from a
		// list the runner has not confirmed.
		await races.nth(1).getByLabel('Name', { exact: true }).fill(`${tuneUp.name} `);
		await expect(preview).toHaveCount(0);
		await races.nth(1).getByLabel('Name', { exact: true }).fill(tuneUp.name);
		await page.getByRole('button', { name: 'Confirm races and preview plans' }).click();

		await page.getByRole('button', { name: 'Create 2 plans' }).click();
		await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 20_000 });

		const admin = getAdminClient();
		const plans = await readRows(
			'the season plans',
			admin
				.from('training_plans')
				.select('id, name, start_date, end_date, status, goal_time_seconds')
				.eq('user_id', runner.id)
				.order('start_date')
		);
		expect(plans.map((p) => [p.name, p.end_date, p.status])).toEqual([
			[first.name, first.date, 'active'],
			[second.name, second.date, 'active'],
		]);
		expect(plans[0].goal_time_seconds).toBe(48 * 60);
		expect(plans[1].start_date > plans[0].end_date).toBe(true);
		expect(new URL(page.url()).pathname).toBe(`/plans/${plans[0].id}`);

		const raceRows = async (planId: string) => {
			const weeks = await readRows('weeks of a season plan', admin.from('plan_weeks').select('id').eq('plan_id', planId));
			const rows = await readRows(
				'race workouts of a season plan',
				admin
					.from('plan_workouts')
					.select('scheduled_date, race_name, race_priority, target_distance_m')
					.in('week_id', weeks.map((w) => w.id))
					.eq('kind', 'race')
					.order('scheduled_date')
			);
			return rows.map((w) => [w.scheduled_date, w.race_name, w.race_priority, Number(w.target_distance_m)]);
		};
		expect(await raceRows(plans[0].id)).toEqual([[first.date, first.name, 'A', 10_000]]);
		expect(await raceRows(plans[1].id)).toEqual([
			[tuneUp.date, tuneUp.name, 'B', 10_000],
			[second.date, second.name, 'A', 21_097.5],
		]);
	} finally {
		await getAdminClient().from('training_plans').delete().eq('user_id', runner.id);
		await context.close();
	}
});

test('an unavailable race extraction leaves a race to fill in by hand', async ({ browser }) => {
	const [runner] = users;
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await context.newPage();
	try {
		await page.route('**/api/coach/season-request', (route) => route.fulfill({ status: 503, body: '' }));
		await open(page);
		await page
			.getByRole('textbox', { name: 'Describe your season' })
			.fill('Richmond Marathon in November, then Comrades in June');
		await page.getByRole('button', { name: 'Find my races' }).click();
		await expect(page.getByTestId('season-request-error')).toContainText("isn't available");
		const races = page.getByTestId('season-race');
		await expect(races).toHaveCount(1);
		await expect(races.nth(0).getByRole('combobox', { name: 'Priority' })).toHaveValue('A');
		await expect(page.getByTestId('season-preview')).toHaveCount(0);
	} finally {
		await context.close();
	}
});

test('races found in a description fill the list with the assumptions explained, and a 56 km + 90 km season chains', async ({
	browser,
	mockRoute,
}) => {
	const [runner] = users;
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await context.newPage();
	const twoOceans = { name: 'Two Oceans e2e', date: browserDate(84), distanceM: 56_000, priority: 'A', goalTimeSec: 6 * 3600 };
	const comrades = { name: 'Comrades e2e', date: browserDate(154), distanceM: 90_000, priority: 'A', goalTimeSec: null };
	try {
		await mockRoute(page, '**/api/coach/season-request', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ races: [twoOceans, comrades], assumptions: ['race_date_next_year', 'priority_a_assigned'] }),
			})
		);
		await open(page);
		await page.getByRole('textbox', { name: 'Describe your season' }).fill('Two Oceans in April then Comrades in June');
		await page.getByRole('button', { name: 'Find my races' }).click();

		const assumptions = page.getByTestId('season-assumptions').getByRole('listitem');
		await expect(assumptions).toHaveText([
			'A date given without a year had already passed this year, so it was moved to next year.',
			'No race was marked as your A race, so the longest one is.',
		]);
		const races = page.getByTestId('season-race');
		await expect(races).toHaveCount(2);
		await expect(races.nth(0).getByLabel('Name', { exact: true })).toHaveValue(twoOceans.name);
		await expect(races.nth(0).getByLabel('Date', { exact: true })).toHaveValue(twoOceans.date);
		await expect(races.nth(0).getByLabel('Distance (km)')).toHaveValue('56');
		await expect(races.nth(0).getByLabel('Goal hours')).toHaveValue('6');
		await expect(races.nth(1).getByLabel('Name', { exact: true })).toHaveValue(comrades.name);
		await expect(races.nth(1).getByLabel('Distance (km)')).toHaveValue('90');
		await expect(races.nth(1).getByRole('combobox', { name: 'Priority' })).toHaveValue('A');
		await expect(page.getByTestId('season-preview')).toHaveCount(0);

		await page.getByRole('button', { name: 'Confirm races and preview plans' }).click();
		const preview = page.getByTestId('season-preview');
		await expect(preview.getByTestId('season-refusal')).toHaveCount(0);
		await expect(preview.getByTestId('season-plan')).toHaveCount(2);
		await expect(preview.getByTestId('season-plan').nth(0)).toContainText(twoOceans.name);
		await expect(preview.getByTestId('season-plan').nth(0)).toContainText('56');
		await expect(preview.getByTestId('season-plan').nth(1)).toContainText(comrades.name);
		await expect(preview.getByTestId('season-plan').nth(1)).toContainText('90');
		await expect(preview).toContainText(`Recovery after ${twoOceans.name}`);
		await expect(preview.getByRole('button', { name: 'Create 2 plans' })).toBeEnabled();
	} finally {
		await context.close();
	}
});

test('a description with no usable races explains why and leaves a race to fill in', async ({ browser, mockRoute }) => {
	const [runner] = users;
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await context.newPage();
	try {
		await mockRoute(page, '**/api/coach/season-request', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ races: [], assumptions: ['race_dropped_distance'] }),
			})
		);
		await open(page);
		await page.getByRole('textbox', { name: 'Describe your season' }).fill('A 2 km fun run next month');
		await page.getByRole('button', { name: 'Find my races' }).click();
		await expect(page.getByTestId('season-request-error')).toContainText('No races could be found');
		await expect(page.getByTestId('season-assumptions').getByRole('listitem')).toHaveText([
			"A race was left out because its distance is outside what the planner supports (5 km to 400 km).",
		]);
		await expect(page.getByTestId('season-race')).toHaveCount(1);
		await expect(page.getByTestId('season-race').nth(0).getByLabel('Name', { exact: true })).toHaveValue('');
	} finally {
		await context.close();
	}
});
