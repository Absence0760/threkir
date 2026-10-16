import { readFileSync } from 'node:fs';
import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { deletePlan } from '../fixtures/simulate';

/**
 * A plan with a B race mid-block survives the export menu and a re-import:
 * the file the plan page writes carries each race's name, priority and goal
 * time (decisions § 2009), and pasting it back into /plans/new creates a plan
 * whose race workouts carry the same three fields and whose goal time is the
 * original's. The serializer pair is unit-tested on both platforms; this pins
 * the UI wiring at both ends — `buildExport` on the plan page and the import
 * box feeding `create_training_plan`.
 *
 * Runs as a throwaway user: the import creates an active plan, and the source
 * plan is deleted before it so the re-import does not overlap anything.
 */

const PLAN_NAME = 'e2e race roundtrip';
const B_RACE = 'Spring 10K e2e';
const A_RACE = 'Goal Half e2e';
const B_GOAL_SEC = 45 * 60;
const PLAN_GOAL_SEC = 1 * 3600 + 39 * 60 + 30;

let users: SagaUser[] = [];

test.beforeAll(async () => {
	users = await createSagaUsers(1, { displayNames: ['Roundtrip Runner'] });
});

test.afterAll(async () => {
	await deleteSagaUsers(users);
});

type RaceRow = [string, string, string | null, string | null, number | null];

function expectedRaces(): RaceRow[] {
	return [
		[browserDate(21), 'race', B_RACE, 'B', B_GOAL_SEC],
		[browserDate(35), 'race', A_RACE, 'A', null],
	];
}

async function plantRacePlan(userId: string): Promise<string> {
	const admin = getAdminClient();
	const planId = crypto.randomUUID();
	const { error: planErr } = await admin.from('training_plans').insert({
		id: planId,
		user_id: userId,
		name: PLAN_NAME,
		goal_event: 'distance_half',
		goal_distance_m: 21097.5,
		goal_time_seconds: PLAN_GOAL_SEC,
		start_date: browserDate(7),
		end_date: browserDate(35),
		days_per_week: 4,
		status: 'active',
	});
	if (planErr) throw planErr;
	const weekIds = Array.from({ length: 5 }, () => crypto.randomUUID());
	const { error: weekErr } = await admin.from('plan_weeks').insert(
		weekIds.map((id, i) => ({ id, plan_id: planId, week_index: i, phase: 'base', target_volume_m: 20_000 })),
	);
	if (weekErr) throw weekErr;
	const { error: woErr } = await admin.from('plan_workouts').insert([
		{ week_id: weekIds[0], scheduled_date: browserDate(7), kind: 'easy', target_distance_m: 8_000 },
		{ week_id: weekIds[1], scheduled_date: browserDate(14), kind: 'long', target_distance_m: 16_000 },
		{
			week_id: weekIds[2],
			scheduled_date: browserDate(21),
			kind: 'race',
			target_distance_m: 10_000,
			target_duration_seconds: B_GOAL_SEC,
			race_name: B_RACE,
			race_priority: 'B',
		},
		{ week_id: weekIds[3], scheduled_date: browserDate(28), kind: 'easy', target_distance_m: 6_000 },
		{
			week_id: weekIds[4],
			scheduled_date: browserDate(35),
			kind: 'race',
			target_distance_m: 21_100,
			race_name: A_RACE,
			race_priority: 'A',
		},
	]);
	if (woErr) throw woErr;
	return planId;
}

async function exportPlan(page: Page, planId: string, item: RegExp): Promise<string> {
	await page.goto(`/plans/${planId}`);
	await expect(page.getByRole('heading', { level: 1, name: PLAN_NAME })).toBeVisible({ timeout: 10_000 });
	await page.locator('.export-menu summary').click();
	const [download] = await Promise.all([page.waitForEvent('download'), page.getByRole('menuitem', { name: item }).click()]);
	return readFileSync(await download.path(), 'utf-8');
}

async function importAndCreate(page: Page, text: string): Promise<string> {
	await page.goto('/plans/new');
	// Scoped to the wizard's own form: the starter picker on this page carries
	// buttons of its own, and its labels are not this spec's business.
	const form = page.locator('form.plan-editor');
	await expect(form.locator('.week-item').first()).toBeVisible({ timeout: 10_000 });
	await page.getByText('Import a plan', { exact: true }).click();
	await page.getByRole('textbox', { name: 'Import a plan' }).fill(text);
	await page.getByRole('button', { name: 'Load plan' }).click();
	await expect(form.locator('.imported-note')).toBeVisible();
	await expect(form.locator('.week-item')).toHaveCount(5);

	const submit = form.locator('button[type="submit"]');
	await expect(submit).toBeEnabled({ timeout: 5_000 });
	await submit.click();
	await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
	return new URL(page.url()).pathname.split('/').pop()!;
}

async function racesOf(planId: string): Promise<RaceRow[]> {
	const admin = getAdminClient();
	const weeks = await readRows('weeks of the re-imported plan', admin.from('plan_weeks').select('id').eq('plan_id', planId));
	const rows = await readRows(
		'race workouts of the re-imported plan',
		admin
			.from('plan_workouts')
			.select('scheduled_date, kind, race_name, race_priority, target_duration_seconds')
			.in('week_id', weeks.map((w) => w.id))
			.eq('kind', 'race')
			.order('scheduled_date'),
	);
	return rows.map((w) => [w.scheduled_date, w.kind, w.race_name, w.race_priority, w.target_duration_seconds]);
}

for (const [format, item] of [
	['Markdown', /Download \.md/],
	['JSON', /Download \.json/],
] as const) {
	test(`a plan with a B race keeps its races through a ${format} export and re-import`, async ({ browser }) => {
		test.setTimeout(90_000);
		const [runner] = users;
		const sourceId = await plantRacePlan(runner.id);
		const context = await browser.newContext({ storageState: runner.storageStatePath });
		const page = await context.newPage();
		try {
			const text = await exportPlan(page, sourceId, item);
			if (format === 'Markdown') {
				expect(text).toContain('| Week | Date | Type | Distance | Pace | Notes | Race | Priority | Goal |');
				expect(text).toContain(`| ${B_RACE} | B | 0:45:00 |`);
			} else {
				expect(JSON.parse(text).workouts).toEqual(
					expect.arrayContaining([expect.objectContaining({ race_name: B_RACE, race_priority: 'B', target_duration_seconds: B_GOAL_SEC })]),
				);
			}

			await deletePlan(sourceId);
			const newId = await importAndCreate(page, text);
			expect(newId).not.toBe(sourceId);

			const races = page.getByRole('region', { name: 'Races in this plan' });
			await expect(races).toBeVisible({ timeout: 10_000 });
			await expect(races.getByRole('listitem')).toHaveCount(2);
			await expect(races.getByRole('listitem').nth(0)).toContainText(B_RACE);
			await expect(races.getByRole('listitem').nth(0).getByLabel('Priority B')).toBeVisible();
			await expect(races.getByRole('listitem').nth(1)).toContainText(A_RACE);

			expect(await racesOf(newId)).toEqual(expectedRaces());
			const plan = await readRow(
				're-imported plan head',
				getAdminClient().from('training_plans').select('name, goal_time_seconds, start_date, end_date').eq('id', newId).single(),
			);
			expect(plan).toEqual({
				name: PLAN_NAME,
				goal_time_seconds: PLAN_GOAL_SEC,
				start_date: browserDate(7),
				end_date: browserDate(35),
			});
			await deletePlan(newId);
		} finally {
			await context.close();
		}
	});
}
