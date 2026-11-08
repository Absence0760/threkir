import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';
import type { MockRoute } from '../fixtures/mock-route';
import { browserDate } from '../fixtures/dates';
import { readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * Changes to a coach-assigned plan go to the coach for approval (issue #1215
 * Phase 2, decisions § 2382).
 *
 * USER_B (alex) is the athlete and owns the plan; USER_C_PRO (morgan) is the
 * coach who assigned it, with an active link. The athlete sends an AI-proposed
 * edit (the plan-edit endpoint mocked, as in ai-plan-edit.spec.ts) to the
 * coach instead of applying it; the coach approves some of its lines from the
 * plan page or declines from the DM thread; the athlete can withdraw or apply
 * it themselves. Every write is read back from the database.
 */

const admin = getAdminClient();
let planId: string;
let easyId: string;
let tempoId: string;
let linkId: string;

async function seed(): Promise<void> {
	planId = crypto.randomUUID();
	const week0 = crypto.randomUUID();
	easyId = crypto.randomUUID();
	tempoId = crypto.randomUUID();
	linkId = crypto.randomUUID();
	await admin.from('coach_athletes').delete().eq('coach_id', USER_C_PRO.id).eq('athlete_id', USER_B.id);
	const { error: linkErr } = await admin.from('coach_athletes').insert({
		id: linkId,
		coach_id: USER_C_PRO.id,
		athlete_id: USER_B.id,
		status: 'active',
		invite_token: `e2e-plan-change-${linkId}`,
		accepted_at: new Date().toISOString(),
	});
	expect(linkErr).toBeNull();
	const { error: planErr } = await admin.from('training_plans').insert({
		id: planId,
		user_id: USER_B.id,
		name: 'e2e coach review',
		goal_event: 'distance_half',
		goal_distance_m: 21097,
		start_date: browserDate(0),
		end_date: browserDate(13),
		status: 'active',
		days_per_week: 4,
		assigned_by_coach_id: USER_C_PRO.id,
	});
	expect(planErr).toBeNull();
	await admin.from('plan_weeks').insert([
		{ id: week0, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 32_000 },
	]);
	await admin.from('plan_workouts').insert([
		{ id: easyId, week_id: week0, scheduled_date: browserDate(1), kind: 'easy', target_distance_m: 8_000 },
		{ id: tempoId, week_id: week0, scheduled_date: browserDate(3), kind: 'tempo', target_distance_m: 8_000 },
	]);
}

async function cleanUp(): Promise<void> {
	await admin.from('training_plans').delete().eq('id', planId);
	await admin.from('coach_athletes').delete().eq('id', linkId);
}

/// A pending request moving the easy run a day later and easing the tempo's
/// distance, filed the way propose_plan_change files one.
async function seedRequest(): Promise<string> {
	const id = crypto.randomUUID();
	const { error } = await admin.from('plan_change_requests').insert({
		id,
		plan_id: planId,
		athlete_id: USER_B.id,
		coach_id: USER_C_PRO.id,
		include_following: false,
		workouts: [
			{ id: easyId, scheduled_date: browserDate(2) },
			{ id: tempoId, target_distance_m: 7_000 },
		],
		weeks: [],
	});
	expect(error).toBeNull();
	return id;
}

async function readWorkout(id: string) {
	return readRow(
		'plan workout',
		admin.from('plan_workouts').select('scheduled_date, target_distance_m').eq('id', id).single(),
	);
}

async function readRequest(id: string) {
	return readRow(
		'plan change request',
		admin.from('plan_change_requests').select('status, edited_by_coach, coach_note, workouts').eq('id', id).single(),
	);
}

test.describe('athlete — send a change to the coach', () => {
	test.use({ storageState: USER_B.storageStatePath });
	test.beforeEach(seed);
	test.afterEach(cleanUp);

	async function suggest(page: Page, mockRoute: MockRoute) {
		await mockRoute(page, '**/api/coach/plan-edit', async (route) => {
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					ops: [{ op: 'move_workout', workoutId: easyId, date: browserDate(2) }],
					dropped: 0,
					notes: [],
					today: browserDate(0),
				}),
			});
		});
		await page.goto(`/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: 'e2e coach review' })).toBeVisible({
			timeout: 10_000,
		});
		await page.getByRole('button', { name: 'Adjust plan' }).click();
		await page.getByTestId('adjust-plan-dialog').getByRole('button', { name: 'Adjust with AI' }).click();
		const box = page.getByTestId('ai-adjust');
		await box.getByRole('textbox', { name: 'Adjust with AI' }).fill('move my easy run a day later');
		await box.getByRole('button', { name: 'Suggest changes' }).click();
		await expect(box).toContainText('Suggested changes', { timeout: 10_000 });
		return box;
	}

	test('the change goes to the coach and the plan is left as it was', async ({ page, mockRoute }) => {
		const box = await suggest(page, mockRoute);
		await expect(box.getByTestId('ai-adjust-coach-hint')).toBeVisible();
		await expect(box.getByRole('button', { name: 'Apply anyway' })).toBeVisible();
		await box.getByTestId('ai-adjust-send').click();
		await expect(page.getByTestId('ai-adjust-sent')).toBeVisible({ timeout: 10_000 });

		const rows = await readRows(
			'plan change requests on the plan',
			admin.from('plan_change_requests').select('status, coach_id, workouts').eq('plan_id', planId),
		);
		expect(rows).toHaveLength(1);
		expect(rows[0].status).toBe('pending');
		expect(rows[0].coach_id).toBe(USER_C_PRO.id);
		expect(rows[0].workouts).toEqual([{ id: easyId, scheduled_date: browserDate(2) }]);
		expect((await readWorkout(easyId)).scheduled_date).toBe(browserDate(1));
		const notices = await readRows(
			'coach notifications',
			admin
				.from('notifications')
				.select('kind')
				.eq('user_id', USER_C_PRO.id)
				.eq('plan_id', planId)
				.eq('kind', 'plan_change_request'),
		);
		expect(notices).toHaveLength(1);
	});

	test('with the coaching link ended, there is nobody to send it to', async ({ page, mockRoute }) => {
		await admin.from('coach_athletes').update({ status: 'ended', ended_at: new Date().toISOString() }).eq('id', linkId);
		const box = await suggest(page, mockRoute);
		await expect(box.getByRole('button', { name: 'Apply AI-suggested changes' })).toBeVisible();
		await expect(box.getByTestId('ai-adjust-send')).toHaveCount(0);
	});

	test('the athlete withdraws a pending request from the conversation', async ({ page }) => {
		const id = await seedRequest();
		await page.goto(`/messages/${USER_C_PRO.id}`);
		const card = page.getByTestId('plan-change-request');
		await expect(card).toContainText('Waiting for your coach to answer', { timeout: 10_000 });
		await card.getByTestId('plan-change-withdraw').click();
		await page.getByTestId('plan-change-withdraw-confirm').getByRole('button', { name: 'Withdraw' }).click();
		await expect.poll(async () => (await readRequest(id)).status).toBe('withdrawn');
		expect((await readWorkout(easyId)).scheduled_date).toBe(browserDate(1));
	});

	test('the athlete applies a pending request themselves', async ({ page }) => {
		const id = await seedRequest();
		await page.goto(`/plans/${planId}`);
		const card = page.getByTestId('plan-change-request');
		await card.getByTestId('plan-change-apply-myself').click({ timeout: 10_000 });
		await expect.poll(async () => (await readRequest(id)).status).toBe('overridden');
		expect((await readWorkout(easyId)).scheduled_date).toBe(browserDate(2));
		expect(Number((await readWorkout(tempoId)).target_distance_m)).toBe(7_000);
	});
});

test.describe('coach — approve or decline', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });
	test.beforeEach(seed);
	test.afterEach(cleanUp);

	test('the coach approves one line of two from the plan page', async ({ page }) => {
		const id = await seedRequest();
		await page.goto(`/plans/${planId}`);
		const card = page.getByTestId('plan-change-request');
		await expect(card).toContainText('Your athlete is waiting for your answer', { timeout: 10_000 });
		const toggles = card.getByTestId('plan-change-line-toggle');
		await expect(toggles).toHaveCount(2);
		// Lines sort by their current day: the easy run first, the tempo second.
		await toggles.nth(1).uncheck();
		await card.getByRole('button', { name: 'Approve selected' }).click();

		await expect.poll(async () => (await readRequest(id)).status).toBe('approved');
		const req = await readRequest(id);
		expect(req.edited_by_coach).toBe(true);
		expect(req.workouts).toEqual([{ id: easyId, scheduled_date: browserDate(2) }]);
		expect((await readWorkout(easyId)).scheduled_date).toBe(browserDate(2));
		expect(Number((await readWorkout(tempoId)).target_distance_m)).toBe(8_000);
	});

	test('the coach declines from the conversation with a note', async ({ page }) => {
		const id = await seedRequest();
		await page.goto(`/messages/${USER_B.id}`);
		const card = page.getByTestId('plan-change-request');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await card.getByTestId('plan-change-note-input').fill('Keep the tempo this week.');
		await card.getByTestId('plan-change-decline').click();

		await expect.poll(async () => (await readRequest(id)).status).toBe('declined');
		expect((await readRequest(id)).coach_note).toBe('Keep the tempo this week.');
		expect((await readWorkout(easyId)).scheduled_date).toBe(browserDate(1));
		await expect(page.getByTestId('plan-change-request')).toContainText('Declined by the coach');
	});
});
