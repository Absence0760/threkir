import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deletePlan } from '../fixtures/simulate';
import { USER_B } from '../fixtures/users';

/**
 * Plan chaining (decisions § 2008): several plans may be active as long as
 * their windows do not overlap. A new plan that misses every active plan is
 * created with no replace dialog and queues as "upcoming"; one that overlaps
 * asks first and can end the old plan the day before it starts.
 * Shifting a plan's dates checks the plans around it first (decisions § 2052):
 * onto a queued plan it offers to move that plan too, onto the plan before it
 * it refuses.
 *
 * Every create path asks the server to refuse an overlap and resolves it
 * only once the runner has chosen (decisions § 2050): the wizard, a starter
 * plan and a public-library clone all show the same dialog, and a plan that
 * appears after the wizard opened is named rather than silently replaced.
 * Ending a plan early over a completed workout is refused by the server
 * (TR001, decisions § 2062) and the wizard says why.
 *
 * Runs as USER_B with a planted active plan, so USER_A's seeded "Richmond
 * Half 2026" — which other specs need active and untrimmed — is never touched.
 * Every USER_B plan this file makes is deleted afterwards.
 */

const BASE_NAME = 'e2e chain base';
const STARTER_NAME = 'Couch to 5K (beginner walk-run)';

/// The wizard snaps its start date to a Sunday, so the spec picks one itself
/// and the date it asserts is the date the plan actually starts on.
function sundayOnOrAfter(offsetDays: number): string {
	const d = new Date(browserDate(offsetDays) + 'T00:00:00Z');
	d.setUTCDate(d.getUTCDate() + ((7 - d.getUTCDay()) % 7));
	return d.toISOString().slice(0, 10);
}

function dayBefore(iso: string): string {
	const d = new Date(iso + 'T00:00:00Z');
	d.setUTCDate(d.getUTCDate() - 1);
	return d.toISOString().slice(0, 10);
}

async function deleteUserBPlans(): Promise<void> {
	for (const pattern of ['e2e chain%', STARTER_NAME]) {
		const rows = await readRows(
			`USER_B plans named ${pattern}`,
			getAdminClient().from('training_plans').select('id').eq('user_id', USER_B.id).like('name', pattern)
		);
		for (const row of rows) await deletePlan(row.id);
	}
}

async function plantPlanRow(fields: {
	name: string;
	start: string;
	end: string;
	status?: string;
	isPublicTemplate?: boolean;
}): Promise<string> {
	const admin = getAdminClient();
	const planId = crypto.randomUUID();
	const template = fields.isPublicTemplate === true;
	const { error } = await admin.from('training_plans').insert({
		id: planId,
		user_id: USER_B.id,
		name: fields.name,
		goal_event: 'distance_10k',
		goal_distance_m: 10_000,
		start_date: fields.start,
		end_date: fields.end,
		days_per_week: 4,
		status: fields.status ?? 'active',
		is_template: template,
		is_public_template: template
	});
	if (error) throw error;
	const weekId = crypto.randomUUID();
	const { error: weekErr } = await admin
		.from('plan_weeks')
		.insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 10_000 });
	if (weekErr) throw weekErr;
	const { error: woErr } = await admin
		.from('plan_workouts')
		.insert({ week_id: weekId, scheduled_date: fields.start, kind: 'easy', target_distance_m: 5_000 });
	if (woErr) throw woErr;
	return planId;
}

async function planStatus(id: string): Promise<{ status: string; end_date: string }> {
	return readRow(
		`plan ${id}`,
		getAdminClient().from('training_plans').select('status, end_date').eq('id', id).single()
	);
}

async function userBPlanIdsNamed(name: string): Promise<{ id: string }[]> {
	return readRows(
		`USER_B plans named ${name}`,
		getAdminClient().from('training_plans').select('id').eq('user_id', USER_B.id).eq('name', name)
	);
}

async function plantBasePlan(endOffsetDays: number): Promise<{ planId: string; weekId: string; lateWorkoutDate: string }> {
	const admin = getAdminClient();
	const planId = crypto.randomUUID();
	const weekId = crypto.randomUUID();
	const lateWorkoutDate = browserDate(endOffsetDays - 2);
	const { error: planErr } = await admin.from('training_plans').insert({
		id: planId,
		user_id: USER_B.id,
		name: BASE_NAME,
		goal_event: 'distance_half',
		goal_distance_m: 21097,
		start_date: browserDate(-7),
		end_date: browserDate(endOffsetDays),
		days_per_week: 4,
		status: 'active'
	});
	if (planErr) throw planErr;
	const { error: weekErr } = await admin
		.from('plan_weeks')
		.insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 30_000 });
	if (weekErr) throw weekErr;
	const { error: woErr } = await admin.from('plan_workouts').insert([
		{ week_id: weekId, scheduled_date: browserDate(0), kind: 'easy', target_distance_m: 6_000 },
		{ week_id: weekId, scheduled_date: lateWorkoutDate, kind: 'easy', target_distance_m: 6_000 }
	]);
	if (woErr) throw woErr;
	return { planId, weekId, lateWorkoutDate };
}

async function openWizardAndSubmit(
	page: import('@playwright/test').Page,
	name: string,
	startIso: string,
	beforeSubmit?: () => Promise<void>
) {
	await page.goto('/plans');
	await expect(page.locator('.card', { hasText: BASE_NAME })).toBeVisible({ timeout: 10_000 });
	await page.getByRole('button', { name: /New plan/ }).first().click();
	const modal = page.locator('.modal');
	await expect(modal).toBeVisible({ timeout: 5_000 });
	await modal.getByPlaceholder('Autumn half marathon').fill(name);
	await modal.locator('input[type="date"]').first().fill(startIso);
	const submit = modal.getByRole('button', { name: /Create plan/ });
	await expect(submit).toBeEnabled({ timeout: 5_000 });
	await beforeSubmit?.();
	await submit.click();
}

/// A USER_B plan with one week and one workout per entry of `workouts`.
async function plantPlan(opts: {
	name: string;
	startOffset: number;
	endOffset: number;
	status?: 'active' | 'paused';
	workouts?: Record<string, unknown>[];
}): Promise<{ planId: string; weekId: string }> {
	const admin = getAdminClient();
	const planId = crypto.randomUUID();
	const weekId = crypto.randomUUID();
	const { error: planErr } = await admin.from('training_plans').insert({
		id: planId,
		user_id: USER_B.id,
		name: opts.name,
		goal_event: 'distance_half',
		goal_distance_m: 21097,
		start_date: browserDate(opts.startOffset),
		end_date: browserDate(opts.endOffset),
		days_per_week: 4,
		status: opts.status ?? 'active'
	});
	if (planErr) throw planErr;
	const { error: weekErr } = await admin
		.from('plan_weeks')
		.insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 30_000 });
	if (weekErr) throw weekErr;
	const rows = (opts.workouts ?? [{ scheduled_date: browserDate(opts.startOffset), kind: 'easy', target_distance_m: 6_000 }])
		.map((w) => ({ week_id: weekId, ...w }));
	const { error: woErr } = await admin.from('plan_workouts').insert(rows);
	if (woErr) throw woErr;
	return { planId, weekId };
}

async function openAdjust(page: import('@playwright/test').Page, planId: string, heading: string) {
	await page.goto(`/plans/${planId}`);
	await expect(page.getByRole('heading', { level: 1, name: heading })).toBeVisible({ timeout: 10_000 });
	await page.getByRole('button', { name: 'Adjust plan' }).click();
	const dialog = page.getByTestId('adjust-plan-dialog');
	await expect(dialog).toBeVisible();
	return dialog;
}

test.describe('plan chaining', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test.beforeEach(deleteUserBPlans);
	test.afterEach(deleteUserBPlans);

	test('a plan after the active one is created with no replace dialog and queues as upcoming', async ({
		page
	}) => {
		await plantBasePlan(20);
		const name = 'e2e chain next';
		await openWizardAndSubmit(page, name, sundayOnOrAfter(28));

		await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
		await expect(page.getByTestId('plan-overlap-dialog')).toHaveCount(0);

		await page.goto('/plans');
		const base = page.locator('.card', { hasText: BASE_NAME });
		const next = page.locator('.card', { hasText: name });
		await expect(base.locator('.badge.status-active')).toBeVisible({ timeout: 10_000 });
		await expect(next.locator('.badge.status-upcoming')).toBeVisible();
		await expect(next.locator('.badge')).toContainText(/upcoming/i);

		const active = await readRows(
			'USER_B active plans',
			getAdminClient().from('training_plans').select('name, status').eq('user_id', USER_B.id).eq('status', 'active')
		);
		expect(active.map((p) => p.name).sort()).toEqual([BASE_NAME, name].sort());
	});

	test('an overlapping plan asks first, and ending the old plan early trims it to the day before', async ({
		page
	}) => {
		const { planId, weekId, lateWorkoutDate } = await plantBasePlan(60);
		const start = sundayOnOrAfter(14);
		const trimTo = dayBefore(start);
		await openWizardAndSubmit(page, 'e2e chain overlap', start);

		const dialog = page.getByTestId('plan-overlap-dialog');
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await expect(dialog).toContainText(BASE_NAME);
		await dialog.getByRole('button', { name: new RegExp(`^End .*${BASE_NAME}`) }).click();

		await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });

		expect(await planStatus(planId)).toEqual({ status: 'active', end_date: trimTo });

		const left = await readRows(
			'the trimmed plan workouts',
			getAdminClient().from('plan_workouts').select('scheduled_date').eq('week_id', weekId)
		);
		const dates = left.map((w) => w.scheduled_date);
		expect(dates).toContain(browserDate(0));
		expect(dates).not.toContain(lateWorkoutDate);
	});

	test('ending a plan early is refused, and says why, when it has completed workouts after the cut', async ({
		page
	}) => {
		const { planId, weekId, lateWorkoutDate } = await plantBasePlan(60);
		const { error: doneErr } = await getAdminClient()
			.from('plan_workouts')
			.update({ manually_completed: true, completed_at: new Date().toISOString() })
			.eq('week_id', weekId)
			.eq('scheduled_date', lateWorkoutDate);
		if (doneErr) throw doneErr;
		const start = sundayOnOrAfter(14);
		await openWizardAndSubmit(page, 'e2e chain ran ahead', start);

		const dialog = page.getByTestId('plan-overlap-dialog');
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: new RegExp(`^End .*${BASE_NAME}`) }).click();

		await expect(page.locator('.modal .error')).toContainText(
			`${BASE_NAME} has completed workouts after`,
			{ timeout: 10_000 }
		);
		await expect(page.locator('.modal .error')).toContainText('Replace it instead, or start the new plan later.');
		expect(await planStatus(planId)).toEqual({ status: 'active', end_date: browserDate(60) });
		expect(await userBPlanIdsNamed('e2e chain ran ahead')).toHaveLength(0);
	});

	test('shifting into a queued plan offers to move it too, and both plans move', async ({ page }) => {
		const { planId: baseId } = await plantBasePlan(20);
		const queuedName = 'e2e chain queued';
		const { planId: queuedId, weekId: queuedWeek } = await plantPlan({
			name: queuedName,
			startOffset: 21,
			endOffset: 60,
			workouts: [{ scheduled_date: browserDate(24), kind: 'easy', target_distance_m: 6_000 }]
		});

		const dialog = await openAdjust(page, baseId, BASE_NAME);
		await dialog.getByLabel('Days to shift (negative moves earlier)').fill('7');
		await dialog.getByRole('button', { name: 'Shift dates' }).click();

		const confirm = page.getByTestId('bulk-confirm-dialog');
		await expect(confirm).toContainText(queuedName, { timeout: 5_000 });
		await confirm.getByRole('button', { name: `Also move ${queuedName} by 7 days` }).click();

		const admin = getAdminClient();
		await expect
			.poll(
				async () =>
					(
						await readRow(
							'the queued plan',
							admin.from('training_plans').select('start_date').eq('id', queuedId).single()
						)
					).start_date
			)
			.toBe(browserDate(28));
		const base = await readRow(
			'the shifted base plan',
			admin.from('training_plans').select('start_date, end_date').eq('id', baseId).single()
		);
		expect(base).toEqual({ start_date: browserDate(0), end_date: browserDate(27) });
		const moved = await readRow(
			'the queued plan workout',
			admin.from('plan_workouts').select('scheduled_date').eq('week_id', queuedWeek).single()
		);
		expect(moved.scheduled_date).toBe(browserDate(31));
	});

	test('shifting back onto the plan before it is refused and nothing moves', async ({ page }) => {
		await plantPlan({ name: 'e2e chain earlier', startOffset: -40, endOffset: -8 });
		const { planId: baseId } = await plantBasePlan(20);

		const dialog = await openAdjust(page, baseId, BASE_NAME);
		await dialog.getByLabel('Days to shift (negative moves earlier)').fill('-3');
		await dialog.getByRole('button', { name: 'Shift dates' }).click();

		await expect(page.locator('.toast.toast-error')).toContainText('e2e chain earlier', { timeout: 5_000 });
		await expect(page.getByTestId('bulk-confirm-dialog')).toBeHidden();
		const base = await readRow(
			'the base plan',
			getAdminClient().from('training_plans').select('start_date').eq('id', baseId).single()
		);
		expect(base.start_date).toBe(browserDate(-7));
	});

	test('resuming a paused plan that overlaps another active plan is refused', async ({ page }) => {
		await plantBasePlan(20);
		const pausedName = 'e2e chain paused';
		const { planId: pausedId } = await plantPlan({ name: pausedName, startOffset: 0, endOffset: 30, status: 'paused' });

		const dialog = await openAdjust(page, pausedId, pausedName);
		await dialog.getByRole('button', { name: 'Resume plan' }).click();
		await page.getByTestId('bulk-confirm-dialog').getByRole('button', { name: 'Apply' }).click();

		await expect(page.locator('.toast.toast-error')).toContainText('Another active plan overlaps these dates', {
			timeout: 5_000
		});
		expect((await planStatus(pausedId)).status).toBe('paused');
	});

	test('the dashboard names the plan queued after the current one as up next', async ({ page }) => {
		await plantBasePlan(20);
		await plantPlan({ name: 'e2e chain queued', startOffset: 21, endOffset: 60 });

		await page.goto('/dashboard');
		await expect(page.getByTestId('plan-hero-next')).toContainText('Up next: e2e chain queued', { timeout: 10_000 });
	});

	test('changing a race workout to another kind clears its race name and priority', async ({ page }) => {
		const { weekId } = await plantPlan({
			name: 'e2e chain races',
			startOffset: -7,
			endOffset: 40,
			workouts: [
				{
					scheduled_date: browserDate(10),
					kind: 'race',
					target_distance_m: 10_000,
					race_name: 'e2e chain tune-up',
					race_priority: 'B'
				}
			]
		});
		const plan = await readRow(
			'the race plan week',
			getAdminClient().from('plan_weeks').select('plan_id').eq('id', weekId).single()
		);

		await page.goto(`/plans/${plan.plan_id}`);
		const raceDay = page.locator('.weeks .week .day .day-link', { hasText: /Race|e2e chain tune-up/ }).first();
		await expect(raceDay).toBeVisible({ timeout: 10_000 });
		await raceDay.click();
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });
		await modal.getByLabel('Kind', { exact: true }).selectOption('easy');
		await modal.getByRole('button', { name: /^Save/ }).click();
		await expect(modal).toHaveCount(0);

		const wo = await readRow(
			'the edited race workout',
			getAdminClient().from('plan_workouts').select('kind, race_name, race_priority').eq('week_id', weekId).single()
		);
		expect(wo).toEqual({ kind: 'easy', race_name: null, race_priority: null });
	});

	test('a race goal time past the editor\'s range is refused and leaves the workout as it was', async ({ page }) => {
		const { weekId } = await plantPlan({
			name: 'e2e chain goal range',
			startOffset: -7,
			endOffset: 40,
			workouts: [
				{
					scheduled_date: browserDate(10),
					kind: 'race',
					target_distance_m: 160_000,
					target_duration_seconds: 30 * 3600,
					race_name: 'e2e chain hundred',
					race_priority: 'B'
				}
			]
		});
		const plan = await readRow(
			'the goal-range plan week',
			getAdminClient().from('plan_weeks').select('plan_id').eq('id', weekId).single()
		);

		await page.goto(`/plans/${plan.plan_id}`);
		const raceDay = page.locator('.weeks .week .day .day-link', { hasText: /Race|e2e chain hundred/ }).first();
		await expect(raceDay).toBeVisible({ timeout: 10_000 });
		await raceDay.click();
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });
		await modal.getByLabel('Goal time hours').fill('1000');
		await modal.getByRole('button', { name: /^Save/ }).click();
		await expect(modal.locator('.error')).toContainText('up to 999 hours');
		await expect(modal).toBeVisible();

		const wo = await readRow(
			'the race workout after the refused save',
			getAdminClient().from('plan_workouts').select('target_duration_seconds').eq('week_id', weekId).single()
		);
		expect(wo.target_duration_seconds).toBe(30 * 3600);
	});

	test('a plan created after the wizard opened is named, not silently replaced', async ({ page }) => {
		await plantBasePlan(20);
		const start = sundayOnOrAfter(28);
		let sneakyId = '';
		await openWizardAndSubmit(page, 'e2e chain late', start, async () => {
			sneakyId = await plantPlanRow({
				name: 'e2e chain sneaky',
				start: dayBefore(start),
				end: browserDate(90)
			});
		});

		const dialog = page.getByTestId('plan-overlap-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await expect(dialog).toContainText('e2e chain sneaky');
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(dialog).toHaveCount(0);

		expect(await planStatus(sneakyId)).toEqual({ status: 'active', end_date: browserDate(90) });
		expect(await userBPlanIdsNamed('e2e chain late')).toHaveLength(0);
	});

	test('a starter plan over an active plan asks first, and Cancel changes nothing', async ({ page }) => {
		const { planId } = await plantBasePlan(60);
		await page.goto('/plans/new?type=training');
		const picker = page.locator('.starter-picker');
		await picker.locator('select').selectOption('c25k');
		await picker.locator('input[type="date"]').fill(sundayOnOrAfter(14));
		await picker.getByRole('button', { name: 'Start this plan' }).click();

		const dialog = page.getByTestId('plan-overlap-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await expect(dialog).toContainText(BASE_NAME);
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(dialog).toHaveCount(0);

		expect((await planStatus(planId)).status).toBe('active');
		expect(await userBPlanIdsNamed(STARTER_NAME)).toHaveLength(0);
	});

	test('a starter plan can replace the active plan it overlaps', async ({ page }) => {
		const { planId } = await plantBasePlan(60);
		await page.goto('/plans/new?type=training');
		const picker = page.locator('.starter-picker');
		await picker.locator('select').selectOption('c25k');
		await picker.locator('input[type="date"]').fill(sundayOnOrAfter(14));
		await picker.getByRole('button', { name: 'Start this plan' }).click();

		const dialog = page.getByTestId('plan-overlap-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByRole('button', { name: 'Replace plan' }).click();
		await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });

		expect((await planStatus(planId)).status).toBe('completed');
	});

	test('a public-library clone over an active plan can end that plan early', async ({ page }) => {
		const { planId } = await plantBasePlan(60);
		const templateId = await plantPlanRow({
			name: 'e2e chain library',
			start: '2030-01-06',
			end: '2030-01-19',
			status: 'completed',
			isPublicTemplate: true
		});
		const start = sundayOnOrAfter(14);
		await page.goto(`/plans/library/${templateId}`);
		await page.locator('.clone-row input[type="date"]').fill(start);
		await page.getByRole('button', { name: 'Clone into my plans' }).click();

		const dialog = page.getByTestId('plan-overlap-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await expect(dialog).toContainText(BASE_NAME);
		await dialog.getByRole('button', { name: new RegExp(`^End .*${BASE_NAME}`) }).click();
		await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });

		expect(await planStatus(planId)).toEqual({ status: 'active', end_date: dayBefore(start) });
	});
});
