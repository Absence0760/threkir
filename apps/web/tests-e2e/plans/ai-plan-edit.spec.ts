import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] — "Adjust with AI" (AI plan edits, decisions § 1979).
 *
 * `/api/coach/plan-edit` is mocked at the network layer, so no Anthropic key
 * is needed: the endpoint's gates (consent v4, plan ownership, the daily cap,
 * the refund) are unit-tested in `src/lib/training/plan_edit/handler.test.ts`
 * and the operation rules in `ops.test.ts` / `apply.test.ts`. Here we pin the
 * page wiring: operations become a before/after diff, nothing is written until
 * "Apply AI-suggested changes", an edit that stacks hard days needs a second
 * confirmation, a consent refusal points at Settings, and the Coach's
 * `?adjust=` handoff runs once. Throwaway plan (status `completed` to dodge the
 * active-plan overlap constraint; editing gates on dates, not status).
 */
test.describe('/plans/[id] — Adjust with AI', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const admin = getAdminClient();
	let planId: string;
	let easyId: string;
	let tempoId: string;
	let longId: string;

	test.beforeEach(async () => {
		planId = crypto.randomUUID();
		const week0 = crypto.randomUUID();
		const week1 = crypto.randomUUID();
		easyId = crypto.randomUUID();
		tempoId = crypto.randomUUID();
		longId = crypto.randomUUID();
		const { error: planErr } = await admin.from('training_plans').insert({
			id: planId,
			user_id: USER_A.id,
			name: 'e2e ai adjust',
			goal_event: 'distance_half',
			goal_distance_m: 21097,
			goal_time_seconds: null,
			start_date: browserDate(0),
			end_date: browserDate(13),
			status: 'completed',
			days_per_week: 4,
		});
		expect(planErr).toBeNull();
		await admin.from('plan_weeks').insert([
			{ id: week0, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 32_000 },
			{ id: week1, plan_id: planId, week_index: 1, phase: 'taper', target_volume_m: 20_000 },
		]);
		await admin.from('plan_workouts').insert([
			{ id: easyId, week_id: week0, scheduled_date: browserDate(1), kind: 'easy', target_distance_m: 8_000 },
			{ id: tempoId, week_id: week0, scheduled_date: browserDate(3), kind: 'tempo', target_distance_m: 8_000 },
			{ id: longId, week_id: week0, scheduled_date: browserDate(5), kind: 'long', target_distance_m: 16_000 },
			{ id: crypto.randomUUID(), week_id: week1, scheduled_date: browserDate(13), kind: 'race', target_distance_m: 21_097 },
		]);
	});

	test.afterEach(async () => {
		await admin.from('training_plans').delete().eq('id', planId);
	});

	async function openAiAdjust(page: import('@playwright/test').Page) {
		await page.goto(`/plans/${planId}`);
		await expect(page.getByRole('heading', { level: 1, name: 'e2e ai adjust' })).toBeVisible({
			timeout: 10_000,
		});
		await page.getByRole('button', { name: 'Adjust plan' }).click();
		await page.getByTestId('adjust-plan-dialog').getByRole('button', { name: 'Adjust with AI' }).click();
		return page.getByTestId('ai-adjust');
	}

	async function readDate(id: string) {
		return (await admin.from('plan_workouts').select('scheduled_date').eq('id', id).single()).data
			?.scheduled_date;
	}

	test('suggested operations show as a diff and are saved only on Apply', async ({ page, mockRoute }) => {
		const seen: { body: Record<string, unknown> | null } = { body: null };
		await mockRoute(page, '**/api/coach/plan-edit', async (route) => {
			seen.body = route.request().postDataJSON();
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					ops: [{ op: 'move_workout', workoutId: easyId, date: browserDate(2) }],
					dropped: 1,
					notes: ['op_dropped'],
					today: browserDate(0),
				}),
			});
		});

		const box = await openAiAdjust(page);
		await box.getByRole('textbox', { name: 'Adjust with AI' }).fill('move my easy run a day later');
		await box.getByRole('button', { name: 'Suggest changes' }).click();

		await expect(box).toContainText('Suggested changes', { timeout: 10_000 });
		await expect(box).toContainText('could not be applied safely');
		expect(seen.body).toMatchObject({ plan_id: planId, request: 'move my easy run a day later' });
		// The server reads the plan; the client never ships it.
		expect(Object.keys(seen.body ?? {}).sort()).toEqual(['plan_id', 'request', 'today']);
		expect(await readDate(easyId)).toBe(browserDate(1));

		await box.getByRole('button', { name: 'Apply AI-suggested changes' }).click();
		await expect.poll(() => readDate(easyId)).toBe(browserDate(2));
		await expect(page.getByTestId('ai-adjust')).toHaveCount(0);
	});

	test('on a generated week of seven rows, a swap and a move onto a rest day save together', async ({
		page,
		mockRoute,
	}) => {
		// A generated week stores a row on every day, rest days included, and a
		// day holds one row. Trading two occupied days used to collide on the
		// per-day uniqueness every time (issue #1186, decisions § 2073).
		const week0 = (await admin.from('plan_workouts').select('week_id').eq('id', easyId).single()).data!
			.week_id;
		const restIds = [0, 2, 4, 6].map(() => crypto.randomUUID());
		const { error: restErr } = await admin.from('plan_workouts').insert(
			[0, 2, 4, 6].map((day, i) => ({
				id: restIds[i],
				week_id: week0,
				scheduled_date: browserDate(day),
				kind: 'rest',
				target_distance_m: null,
			})),
		);
		expect(restErr).toBeNull();

		await mockRoute(page, '**/api/coach/plan-edit', async (route) => {
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					ops: [
						{ op: 'swap_days', workoutId: easyId, otherWorkoutId: tempoId },
						{ op: 'move_workout', workoutId: longId, date: browserDate(6) },
					],
					dropped: 0,
					notes: [],
					today: browserDate(0),
				}),
			});
		});

		const box = await openAiAdjust(page);
		await box.getByRole('textbox', { name: 'Adjust with AI' }).fill('swap my easy run and tempo, long run on Sunday');
		await box.getByRole('button', { name: 'Suggest changes' }).click();
		await expect(box).toContainText('Suggested changes', { timeout: 10_000 });

		await box.getByRole('button', { name: 'Apply AI-suggested changes' }).click();
		await expect(page.getByTestId('ai-adjust')).toHaveCount(0, { timeout: 10_000 });

		expect(await readDate(easyId)).toBe(browserDate(3));
		expect(await readDate(tempoId)).toBe(browserDate(1));
		expect(await readDate(longId)).toBe(browserDate(6));
		expect(await readDate(restIds[3])).toBe(browserDate(5));
		const rows = await readRows(
			'plan_workouts of week 0',
			admin.from('plan_workouts').select('scheduled_date').eq('week_id', week0),
		);
		expect(rows).toHaveLength(7);
		expect(new Set(rows.map((r) => r.scheduled_date)).size).toBe(7);
	});

	test('a skip and an eased week are saved on Apply', async ({ page, mockRoute }) => {
		// Only week 1 stays, so easing it cannot raise a later week's load band
		// against whatever recent runs the shared user carries.
		const { data: weeks } = await admin
			.from('plan_weeks')
			.select('id, week_index')
			.eq('plan_id', planId)
			.order('week_index');
		const [week0, week1] = weeks ?? [];
		await admin.from('plan_workouts').delete().eq('week_id', week1.id);
		await admin.from('plan_weeks').delete().eq('id', week1.id);

		await mockRoute(page, '**/api/coach/plan-edit', async (route) => {
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					ops: [
						{ op: 'scale_week', weekIndex: 0, factor: 0.8 },
						{ op: 'skip_workout', workoutId: tempoId },
					],
					dropped: 0,
					notes: [],
					today: browserDate(0),
				}),
			});
		});

		const box = await openAiAdjust(page);
		await box.getByRole('textbox', { name: 'Adjust with AI' }).fill('make this week easier and drop the tempo');
		await box.getByRole('button', { name: 'Suggest changes' }).click();
		await expect(box).toContainText('Suggested changes', { timeout: 10_000 });
		await expect(box).toContainText('Skipped');
		await expect(box).toContainText('Week 1 target');

		await box.getByRole('button', { name: 'Apply AI-suggested changes' }).click();
		await expect(page.getByTestId('ai-adjust')).toHaveCount(0, { timeout: 10_000 });

		const rows = await readRows(
			'plan_workouts by id',
			admin
				.from('plan_workouts')
				.select('id, target_distance_m, skipped_at')
				.in('id', [easyId, tempoId, longId]),
		);
		const byId = new Map(rows.map((r) => [r.id, r]));
		expect(byId.get(easyId)?.target_distance_m).toBe(6_400);
		expect(byId.get(longId)?.target_distance_m).toBe(12_800);
		expect(byId.get(tempoId)?.skipped_at).not.toBeNull();
		const week = await readRow(
			'plan_weeks by id',
			admin.from('plan_weeks').select('target_volume_m').eq('id', week0.id).single(),
		);
		expect(week.target_volume_m).toBe(25_600);
	});

	test('an edit that stacks hard days needs a second confirmation', async ({ page, mockRoute }) => {
		await mockRoute(page, '**/api/coach/plan-edit', async (route) => {
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					ops: [{ op: 'move_workout', workoutId: longId, date: browserDate(4) }],
					dropped: 0,
					notes: [],
					today: browserDate(0),
				}),
			});
		});

		const box = await openAiAdjust(page);
		await box.getByRole('textbox', { name: 'Adjust with AI' }).fill('long run a day earlier');
		await box.getByRole('button', { name: 'Suggest changes' }).click();
		await expect(box.getByTestId('ai-adjust-warnings')).toContainText('back-to-back', {
			timeout: 10_000,
		});

		await box.getByRole('button', { name: 'Apply AI-suggested changes' }).click();
		const confirm = page.getByTestId('ai-adjust-confirm');
		await expect(confirm).toBeVisible();
		await confirm.getByRole('button', { name: 'Cancel' }).click();
		expect(await readDate(longId)).toBe(browserDate(5));

		await box.getByRole('button', { name: 'Apply AI-suggested changes' }).click();
		await page.getByTestId('ai-adjust-confirm').getByRole('button', { name: 'Apply anyway' }).click();
		await expect.poll(() => readDate(longId)).toBe(browserDate(4));
	});

	test('a consent refusal points at Settings and changes nothing', async ({ page, mockRoute }) => {
		await mockRoute(page, '**/api/coach/plan-edit', async (route) => {
			await route.fulfill({
				status: 403,
				contentType: 'application/json',
				body: JSON.stringify({
					error: 'ai disclosure required',
					code: 'ai_disclosure_required',
					required_version: 4,
				}),
			});
		});

		const box = await openAiAdjust(page);
		await box.getByRole('textbox', { name: 'Adjust with AI' }).fill('make this week easier');
		await box.getByRole('button', { name: 'Suggest changes' }).click();

		const error = box.getByRole('alert');
		await expect(error).toContainText('updated AI disclosure', { timeout: 10_000 });
		await expect(error.getByRole('link')).toHaveAttribute('href', '/settings/account#ai-consent');
		await expect(box.getByRole('button', { name: 'Apply AI-suggested changes' })).toHaveCount(0);
	});

	test('the Coach\'s ?adjust= handoff runs once and leaves the URL', async ({ page, mockRoute }) => {
		const bodies: Array<{ request?: string }> = [];
		await mockRoute(page, '**/api/coach/plan-edit', async (route) => {
			bodies.push(route.request().postDataJSON());
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ ops: [], dropped: 0, notes: ['unsupported'], today: browserDate(0) }),
			});
		});

		const request = 'add a hill session on Wednesday';
		await page.goto(`/plans/${planId}?adjust=${encodeURIComponent(request)}`);
		const box = page.getByTestId('ai-adjust');
		await expect(box).toContainText('not something AI plan edits can do', { timeout: 10_000 });
		await expect(box.getByRole('textbox', { name: 'Adjust with AI' })).toHaveValue(request);
		await expect(page).not.toHaveURL(/adjust=/);
		expect(bodies).toHaveLength(1);
		expect(bodies[0].request).toBe(request);

		await page.reload();
		await expect(page.getByRole('heading', { level: 1, name: 'e2e ai adjust' })).toBeVisible({
			timeout: 10_000,
		});
		await expect(page.getByTestId('ai-adjust')).toHaveCount(0);
		expect(bodies).toHaveLength(1);
	});
});
