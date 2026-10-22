import type { Page } from '@playwright/test';

import { browserDate } from '../fixtures/dates';
import { readRows } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import type { MockRoute } from '../fixtures/mock-route';
import { expect, test } from '../fixtures/test';
import { USER_B } from '../fixtures/users';

/**
 * /coach — a plan edit proposed and applied inside the chat (issue #1213,
 * decisions § 2230). The Coach's reply carries the `[Adjust my plan]` link;
 * the web chat shows the change as a card under it, and nothing is written
 * until Apply, which saves every change through one `apply_ai_plan_edits`
 * call. With a block queued after the plan, the card asks whether the change
 * also reaches it.
 *
 * `/api/coach` and `/api/coach/plan-edit` are stubbed (no Anthropic key); the
 * plans, the reads and the RPC are real. USER_B carries no active plan of its
 * own, so these two active blocks around today cannot collide with the seed.
 */

const admin = getAdminClient();

interface Seeded {
	planId: string;
	nextId: string;
	weekA0: string;
	easyA: string;
	longA: string;
	laterA: string;
	weekF0: string;
	easyF: string;
	taperF: string;
}

async function seed(withNext: boolean): Promise<Seeded> {
	const s: Seeded = {
		planId: crypto.randomUUID(),
		nextId: crypto.randomUUID(),
		weekA0: crypto.randomUUID(),
		easyA: crypto.randomUUID(),
		longA: crypto.randomUUID(),
		laterA: crypto.randomUUID(),
		weekF0: crypto.randomUUID(),
		easyF: crypto.randomUUID(),
		taperF: crypto.randomUUID(),
	};
	const weekA1 = crypto.randomUUID();
	const weekF1 = crypto.randomUUID();
	const plans = [
		{
			id: s.planId,
			user_id: USER_B.id,
			name: 'e2e chat edit block',
			goal_event: 'distance_half',
			goal_distance_m: 21097,
			start_date: browserDate(0),
			end_date: browserDate(13),
			status: 'active',
			days_per_week: 4,
		},
		...(withNext
			? [
					{
						id: s.nextId,
						user_id: USER_B.id,
						name: 'e2e chat edit next block',
						goal_event: 'distance_half',
						goal_distance_m: 21097,
						start_date: browserDate(14),
						end_date: browserDate(27),
						status: 'active',
						days_per_week: 4,
					},
				]
			: []),
	];
	const { error: planErr } = await admin.from('training_plans').insert(plans);
	expect(planErr).toBeNull();
	const { error: weekErr } = await admin.from('plan_weeks').insert([
		{ id: s.weekA0, plan_id: s.planId, week_index: 0, phase: 'build', target_volume_m: 24_000 },
		{ id: weekA1, plan_id: s.planId, week_index: 1, phase: 'build', target_volume_m: 26_000 },
		...(withNext
			? [
					{ id: s.weekF0, plan_id: s.nextId, week_index: 0, phase: 'build', target_volume_m: 30_000 },
					{ id: weekF1, plan_id: s.nextId, week_index: 1, phase: 'taper', target_volume_m: 6_000 },
				]
			: []),
	]);
	expect(weekErr).toBeNull();
	const { error: woErr } = await admin.from('plan_workouts').insert([
		{ id: s.easyA, week_id: s.weekA0, scheduled_date: browserDate(1), kind: 'easy', target_distance_m: 8_000 },
		{ id: s.longA, week_id: s.weekA0, scheduled_date: browserDate(5), kind: 'long', target_distance_m: 16_000 },
		{ id: s.laterA, week_id: weekA1, scheduled_date: browserDate(12), kind: 'long', target_distance_m: 18_000 },
		...(withNext
			? [
					{ id: s.easyF, week_id: s.weekF0, scheduled_date: browserDate(15), kind: 'easy', target_distance_m: 10_000 },
					{ id: s.taperF, week_id: weekF1, scheduled_date: browserDate(22), kind: 'easy', target_distance_m: 6_000 },
				]
			: []),
	]);
	expect(woErr).toBeNull();
	return s;
}

/// The trailing blank line ends the `done` event; without it the stream
/// parser never dispatches it, the reply keeps no id, and no card renders.
function sseBody(reply: string): string {
	return [
		'event: meta',
		`data: ${JSON.stringify({ user_message_id: 'plan-edit-user-msg', tier: 'free', limits: { daily_limit: 10 } })}`,
		'',
		'event: token',
		`data: ${JSON.stringify({ text: reply })}`,
		'',
		'event: done',
		`data: ${JSON.stringify({ assistant_message_id: 'plan-edit-assistant-msg' })}`,
		'',
		'',
	].join('\n');
}

const REQUEST = 'make this week easier';

/// Stub the Coach's reply (the adjust link) and the edit endpoint (one
/// scale of week 1 to 90%), send a message, and return the card.
async function askForEdit(page: Page, mockRoute: MockRoute, planId: string) {
	await mockRoute(page, '**/rest/v1/rpc/get_coach_usage*', (route) =>
		route.fulfill({ status: 200, headers: { 'content-type': 'application/json' }, body: '0' }),
	);
	await mockRoute(page, '**/api/coach', (route) =>
		route.fulfill({
			status: 200,
			headers: { 'content-type': 'text/event-stream', 'cache-control': 'no-cache' },
			body: sseBody(
				'I will not rewrite the plan myself. ' +
					`[Adjust my plan](/plans/${planId}?adjust=${encodeURIComponent(REQUEST)}) ` +
					'shows the suggested changes for you to review; nothing changes until you apply them.',
			),
		}),
	);
	const bodies: Array<Record<string, unknown>> = [];
	await mockRoute(page, '**/api/coach/plan-edit', async (route) => {
		bodies.push(route.request().postDataJSON() as Record<string, unknown>);
		await route.fulfill({
			status: 200,
			contentType: 'application/json',
			body: JSON.stringify({
				ops: [{ op: 'scale_week', weekIndex: 0, factor: 0.9 }],
				dropped: 0,
				notes: [],
				today: browserDate(0),
			}),
		});
	});

	await page.goto(`/coach?plan=${planId}`);
	const composer = page.getByPlaceholder(/Ask about today/);
	await expect(composer).toBeVisible({ timeout: 10_000 });
	await composer.fill('This week feels like too much, can you make it easier?');
	await page.locator('form.composer button[type="submit"]').click();

	const card = page.getByTestId('coach-plan-edit');
	await expect(card).toContainText('Week 1 target', { timeout: 10_000 });
	expect(bodies).toHaveLength(1);
	expect(bodies[0]).toMatchObject({ plan_id: planId, request: REQUEST });
	return card;
}

async function distances(ids: string[]): Promise<Map<string, number>> {
	const rows = await readRows(
		'plan_workouts by id',
		admin.from('plan_workouts').select('id, target_distance_m').in('id', ids),
	);
	return new Map(rows.map((r) => [r.id as string, Number(r.target_distance_m)]));
}

async function weekTarget(id: string): Promise<number> {
	const rows = await readRows('plan_weeks by id', admin.from('plan_weeks').select('target_volume_m').eq('id', id));
	return Number(rows[0]?.target_volume_m);
}

test.describe('/coach — plan edit card', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let seeded: Seeded | null = null;

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
	});

	test.afterEach(async () => {
		if (seeded) {
			await admin.from('training_plans').delete().in('id', [seeded.planId, seeded.nextId]);
			await admin.from('coach_messages').delete().eq('user_id', USER_B.id).eq('plan_id', seeded.planId);
		}
		seeded = null;
	});

	test('the suggested change shows as a diff and Discard writes nothing', async ({ page, mockRoute }) => {
		seeded = await seed(false);
		const card = await askForEdit(page, mockRoute, seeded.planId);

		// No block is queued after this one, so there is no scope to choose.
		await expect(card.getByTestId('coach-plan-edit-scope')).toHaveCount(0);
		await card.getByRole('button', { name: 'Discard' }).click();
		await expect(card).toContainText('Nothing in your plan changed');

		const after = await distances([seeded.easyA, seeded.longA]);
		expect(after.get(seeded.easyA)).toBe(8_000);
		expect(after.get(seeded.longA)).toBe(16_000);
		expect(await weekTarget(seeded.weekA0)).toBe(24_000);
	});

	test('Apply writes every change of the block together', async ({ page, mockRoute }) => {
		seeded = await seed(false);
		const card = await askForEdit(page, mockRoute, seeded.planId);

		await card.getByRole('button', { name: 'Apply', exact: true }).click();
		await expect(card).toContainText('Your plan has been updated', { timeout: 10_000 });

		const after = await distances([seeded.easyA, seeded.longA, seeded.laterA]);
		expect(after.get(seeded.easyA)).toBe(7_200);
		expect(after.get(seeded.longA)).toBe(14_400);
		expect(after.get(seeded.laterA)).toBe(18_000);
		expect(await weekTarget(seeded.weekA0)).toBe(21_600);
	});

	test('with a block queued after it, the runner chooses whether the change reaches it', async ({
		page,
		mockRoute,
	}) => {
		seeded = await seed(true);
		const card = await askForEdit(page, mockRoute, seeded.planId);

		const scope = card.getByTestId('coach-plan-edit-scope');
		await expect(scope).toBeVisible();
		await expect(scope.getByRole('radio', { name: 'This block only' })).toBeChecked();
		await expect(card.getByTestId('coach-plan-edit-block')).toHaveCount(1);

		await scope.getByRole('radio', { name: 'This block and the following blocks in the season' }).check();
		await expect(card.getByTestId('coach-plan-edit-block')).toHaveCount(2);
		await expect(card).toContainText('e2e chat edit next block');

		await card.getByRole('button', { name: 'Apply', exact: true }).click();
		await expect(card).toContainText('Your plan has been updated', { timeout: 10_000 });

		const after = await distances([seeded.easyA, seeded.easyF, seeded.taperF]);
		expect(after.get(seeded.easyA)).toBe(7_200);
		expect(after.get(seeded.easyF)).toBe(9_000);
		// Easing reaches the next block's taper too; only a scale-up stops there.
		expect(after.get(seeded.taperF)).toBe(5_400);
		expect(await weekTarget(seeded.weekF0)).toBe(27_000);
	});
});
