import type { BrowserContext, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { browserDate, browserDayStart, noonOnBrowserDay } from '../fixtures/dates';
import { readMaybeRow, readRow, readRows } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { deletePlan, insertRun } from '../fixtures/simulate';

/**
 * Home surfaces the plan's existing re-plan proposals unprompted, and a done
 * workout run long reads "Completed · +3 km" (issue #1186, decisions
 * § 2125-2127). The engine and the card's rules are unit-tested on both sides
 * (plan_nudges); this pins the surfaces: the card appears for the right
 * occurrence, Review opens the plan's own preview, Dismiss files the
 * occurrence in the prefs bag so it stays gone, a refused dismissal says so,
 * and the over-run shows on every done-workout status line.
 *
 * Every plan starts 23 days ago, so weeks 0-2 are complete and today sits in
 * week 3: week k, day d is offset -23 + 7k + d. Each week plans an easy run on
 * day 3 and a long run on day 6; no other day has a session.
 */
const START = -23;
const day = (week: number, d: number) => START + 7 * week + d;

let user: SagaUser;
let ctx: BrowserContext | undefined;

type WeekSpec = { volume: number; longM?: number; easyM?: number };

async function plantPlan(
	name: string,
	weeks: WeekSpec[],
	opts: { status?: 'active' | 'paused'; today?: { kind: string; distanceM: number } } = {}
): Promise<{ planId: string; workoutIds: Map<string, string> }> {
	const admin = getAdminClient();
	const planId = crypto.randomUUID();
	const { error } = await admin.from('training_plans').insert({
		id: planId,
		user_id: user.id,
		name,
		goal_event: 'distance_half',
		goal_distance_m: 21_097,
		start_date: browserDate(START),
		end_date: browserDate(day(weeks.length, -1)),
		status: opts.status ?? 'active',
		paused_at: opts.status === 'paused' ? new Date().toISOString() : null,
		days_per_week: 3
	});
	if (error) throw error;
	const workoutIds = new Map<string, string>();
	for (const [k, w] of weeks.entries()) {
		const weekId = crypto.randomUUID();
		const { error: weekErr } = await admin
			.from('plan_weeks')
			.insert({ id: weekId, plan_id: planId, week_index: k, phase: 'build', target_volume_m: w.volume });
		if (weekErr) throw weekErr;
		const rows = [
			{ key: `easy${k}`, d: 3, kind: 'easy', target: w.easyM ?? 8_000 },
			{ key: `long${k}`, d: 6, kind: 'long', target: w.longM ?? 20_000 }
		];
		if (opts.today && day(k, 0) <= 0 && 0 < day(k, 7)) {
			rows.push({ key: 'today', d: -day(k, 0), kind: opts.today.kind, target: opts.today.distanceM });
		}
		for (const r of rows) {
			const id = crypto.randomUUID();
			workoutIds.set(r.key, id);
			const { error: woErr } = await admin.from('plan_workouts').insert({
				id,
				week_id: weekId,
				scheduled_date: browserDate(day(k, r.d)),
				kind: r.kind,
				target_distance_m: r.target
			});
			if (woErr) throw woErr;
		}
	}
	return { planId, workoutIds };
}

async function run(offset: number, distanceM: number): Promise<void> {
	await insertRun({
		user_id: user.id,
		started_at: noonOnBrowserDay(offset),
		distance_m: distanceM,
		duration_s: Math.round(distanceM * 0.33)
	});
}

async function dismissed(): Promise<unknown> {
	const row = await readMaybeRow(
		'saga user_settings',
		getAdminClient().from('user_settings').select('prefs').eq('user_id', user.id).maybeSingle()
	);
	return (row?.prefs as Record<string, unknown> | undefined)?.plan_nudges_dismissed;
}

async function openHome(): Promise<Page> {
	const page = await ctx!.newPage();
	await page.goto('/dashboard');
	return page;
}

test.describe('Home plan card and the over-run status', () => {
	test.describe.configure({ mode: 'serial', timeout: 90_000 });

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Nudge Runner'] });
	});
	test.afterAll(async () => {
		await deleteSagaUsers([user]);
	});
	test.beforeEach(async ({ browser }) => {
		ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
	});
	test.afterEach(async () => {
		await ctx?.close();
		ctx = undefined;
		const admin = getAdminClient();
		const plans = await readRows(
			'saga plans',
			admin.from('training_plans').select('id').eq('user_id', user.id)
		);
		for (const p of plans) await deletePlan(p.id);
		await admin.from('runs').delete().eq('user_id', user.id);
		await admin.from('user_settings').delete().eq('user_id', user.id);
	});

	test('a week well over plan offers the ease-off; Review opens the plan preview and applying eases next week', async () => {
		const { planId, workoutIds } = await plantPlan('e2e nudge ease', [
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 }
		]);
		await run(day(0, 6), 28_000);
		await run(day(1, 6), 28_000);
		await run(day(2, 6), 36_000);

		const page = await openHome();
		const card = page.getByTestId('plan-nudge');
		await expect(card).toBeVisible({ timeout: 15_000 });
		await expect(card).toHaveAttribute('data-kind', 'ease_over');
		await expect(card).toContainText('A big week');
		await expect(card).toContainText('You ran well over plan last week.');

		await card.getByRole('button', { name: 'Review the changes' }).click();
		await expect(page).toHaveURL(new RegExp(`/plans/${planId}`));
		const preview = page.locator('.replan-preview');
		await expect(preview).toBeVisible({ timeout: 15_000 });
		// Week 3's easy run (8 km, still ahead) eases to 85%: 6.8 km.
		await expect(preview).toContainText('8.0 km → 6.8 km');
		await expect.poll(dismissed).toEqual([`${planId}:ease_over:2`]);
		// The review request leaves the URL, so a reload proposes nothing again.
		await expect(page).not.toHaveURL(/review=/);

		await preview.getByRole('button', { name: 'Apply changes' }).click();
		await expect
			.poll(
				async () =>
					(
						await readRow(
							'eased easy run',
							getAdminClient()
								.from('plan_workouts')
								.select('target_distance_m')
								.eq('id', workoutIds.get('easy3')!)
								.single()
						)
					).target_distance_m
			)
			.toBe(6_800);

		await page.goto('/dashboard');
		await expect(page.getByTestId('dash-plan-load-error')).toHaveCount(0);
		await expect(page.locator('.plan-hero')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('plan-nudge')).toHaveCount(0);
	});

	test('an under-run trend with a make-up offers the adaptive review, badged as the trend', async () => {
		const { planId, workoutIds } = await plantPlan('e2e nudge under', [
			{ volume: 40_000, longM: 26_000 },
			{ volume: 40_000 },
			{ volume: 28_000 },
			{ volume: 40_000, longM: 22_000 },
			{ volume: 40_000, longM: 22_000 }
		]);
		await run(day(1, 3), 8_000);
		await run(day(1, 6), 20_000);
		await run(day(2, 3), 8_000);
		await run(day(2, 6), 20_000);

		const page = await openHome();
		const card = page.getByTestId('plan-nudge');
		await expect(card).toBeVisible({ timeout: 15_000 });
		await expect(card).toHaveAttribute('data-kind', 'adaptive_under');
		await expect(card).toContainText("You've run less than planned in 2 of the last 3 weeks.");

		await card.getByRole('button', { name: 'Review the changes' }).click();
		const preview = page.locator('.replan-preview');
		await expect(preview).toBeVisible({ timeout: 15_000 });
		await expect(preview.locator('.replan-adaptive-badge')).toHaveText(/under your plan/i);
		await expect.poll(dismissed).toEqual([`${planId}:adaptive_under:2`]);

		// Declining leaves the plan as it was.
		await preview.getByRole('button', { name: 'Cancel' }).click();
		await expect(preview).toHaveCount(0);
		const long3 = await readRow(
			'week 3 long run',
			getAdminClient().from('plan_workouts').select('target_distance_m').eq('id', workoutIds.get('long3')!).single()
		);
		expect(Number(long3.target_distance_m)).toBe(22_000);
	});

	test('runs on rest days in 2 of 3 weeks bring the note; Dismiss files it and it stays gone', async () => {
		const { planId } = await plantPlan('e2e nudge rest', [
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 }
		]);
		await run(day(0, 6), 20_000);
		await run(day(0, 0), 8_000);
		await run(day(1, 6), 20_000);
		await run(day(1, 1), 8_000);
		await run(day(2, 6), 20_000);
		await run(day(2, 3), 8_000);

		const page = await openHome();
		const card = page.getByTestId('plan-nudge');
		await expect(card).toBeVisible({ timeout: 15_000 });
		await expect(card).toHaveAttribute('data-kind', 'rest_day_runs');
		await expect(card).toContainText("You've run on rest days in 2 of the last 3 weeks.");
		await expect(card.getByRole('button', { name: 'Review the changes' })).toHaveCount(0);

		await card.getByRole('button', { name: 'Dismiss this suggestion' }).click();
		await expect(card).toHaveCount(0);
		await expect.poll(dismissed).toEqual([`${planId}:rest_day_runs:2`]);

		await page.reload();
		await expect(page.locator('.plan-hero')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('plan-nudge')).toHaveCount(0);
	});

	test('a refused dismissal keeps the card and says so', async () => {
		await plantPlan('e2e nudge refused', [
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 }
		]);
		await run(day(0, 6), 28_000);
		await run(day(1, 6), 28_000);
		await run(day(2, 6), 36_000);

		const page = await openHome();
		const card = page.getByTestId('plan-nudge');
		await expect(card).toBeVisible({ timeout: 15_000 });
		await page.route(/\/rest\/v1\/rpc\/merge_my_settings\b/, (route) =>
			route.fulfill({
				status: 403,
				contentType: 'application/json',
				body: JSON.stringify({ code: '42501', message: 'permission denied for table user_settings' })
			})
		);
		await card.getByRole('button', { name: 'Dismiss this suggestion' }).click();
		await expect(page.getByText("Couldn't hide that suggestion. Try again.")).toBeVisible();
		await expect(card).toBeVisible();
		await expect(card).toHaveAttribute('data-kind', 'ease_over');
		expect(await dismissed()).toBeUndefined();
	});

	test('at 300px the card wraps instead of scrolling the page', async ({ browser }) => {
		await plantPlan('e2e nudge narrow', [
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 }
		]);
		await run(day(0, 6), 28_000);
		await run(day(1, 6), 28_000);
		await run(day(2, 6), 36_000);
		await ctx?.close();
		ctx = await browser.newContext({ storageState: user.storageStatePath, viewport: { width: 300, height: 720 } });
		await acceptCookieConsent(ctx);
		const page = await openHome();
		const card = page.getByTestId('plan-nudge');
		await expect(card).toBeVisible({ timeout: 15_000 });
		for (const box of [
			await card.boundingBox(),
			await card.locator('.plan-nudge-body').boundingBox(),
			await card.getByRole('button', { name: 'Dismiss this suggestion' }).boundingBox(),
			await card.getByRole('button', { name: 'Review the changes' }).boundingBox()
		]) {
			expect(box).not.toBeNull();
			expect(box!.x).toBeGreaterThanOrEqual(0);
			expect(box!.x + box!.width).toBeLessThanOrEqual(300);
		}
		const { scrollWidth, clientWidth } = await page.evaluate(() => ({
			scrollWidth: document.documentElement.scrollWidth,
			clientWidth: document.documentElement.clientWidth
		}));
		expect(scrollWidth).toBeLessThanOrEqual(clientWidth);
	});

	test('with the comeback ramp gate off, a single short week offers no card and resuming offers no re-anchor', async () => {
		// The gate-on half lives in configured/plan-volume-anchor.spec.ts.
		const short = await plantPlan('e2e nudge anchor off', [
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 },
			{ volume: 28_000 }
		]);
		await run(day(0, 6), 28_000);
		await run(day(1, 6), 28_000);
		await run(day(2, 6), 10_000);

		const page = await openHome();
		await expect(page.locator('.plan-hero')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('plan-nudge')).toHaveCount(0);
		await deletePlan(short.planId);

		const { planId } = await plantPlan(
			'e2e nudge resume off',
			[{ volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }],
			{ status: 'paused' }
		);
		const { error } = await getAdminClient()
			.from('training_plans')
			.update({ paused_at: browserDayStart(day(1, 1)) })
			.eq('id', planId);
		if (error) throw error;
		await page.goto(`/plans/${planId}?resume=1`);
		await expect(page.getByText(/move back 2 weeks/)).toBeVisible({ timeout: 15_000 });
		await page.getByRole('button', { name: 'Apply' }).click();
		await expect(page.getByText('Plan resumed and pushed back 2 weeks.')).toBeVisible();
		await expect(page.locator('.replan-preview')).toHaveCount(0);
	});

	test('a paused plan gets no card', async () => {
		await plantPlan(
			'e2e nudge paused',
			[{ volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }],
			{ status: 'paused' }
		);
		await run(day(0, 6), 28_000);
		await run(day(1, 6), 28_000);
		await run(day(2, 6), 36_000);

		const page = await openHome();
		await expect(page.getByTestId('dash-paused-plan')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('plan-nudge')).toHaveCount(0);
	});

	test('a workout run 3 km long reads "Completed · +3 km" on Home, the plan and the workout', async () => {
		const { planId, workoutIds } = await plantPlan(
			'e2e overrun',
			[{ volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }],
			{ today: { kind: 'tempo', distanceM: 10_000 } }
		);
		await run(0, 13_000);
		const todayId = workoutIds.get('today')!;
		await expect
			.poll(
				async () =>
					(
						await readRow(
							'today workout',
							getAdminClient().from('plan_workouts').select('completed_run_id').eq('id', todayId).single()
						)
					).completed_run_id
			)
			.not.toBeNull();

		const page = await openHome();
		const done = page.getByTestId('plan-hero-done');
		await expect(done).toBeVisible({ timeout: 15_000 });
		await expect(done).toHaveText('Completed · +3 km, 3 km more than planned');

		await page.goto(`/plans/${planId}`);
		await expect(page.getByTestId('plan-today-done')).toHaveText('Completed · +3 km, 3 km more than planned', {
			timeout: 15_000
		});
		const cell = page.locator(`.day[data-status="done"]`).filter({ has: page.getByTestId('plan-day-overrun') });
		await expect(cell.getByTestId('plan-day-overrun')).toHaveText('+3 km');
		await expect(cell.getByRole('button')).toHaveAttribute('aria-label', /, completed.*3 km more than planned$/i);

		await page.goto(`/plans/${planId}/workouts/${todayId}`);
		await expect(page.getByTestId('workout-detail-done')).toHaveText(
			'Completed · +3 km, 3 km more than planned',
			{ timeout: 15_000 }
		);
	});

	test('a workout run a few hundred metres long reads plain "Completed"', async () => {
		const { workoutIds, planId } = await plantPlan(
			'e2e overrun trivial',
			[{ volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }],
			{ today: { kind: 'tempo', distanceM: 10_000 } }
		);
		await run(0, 10_600);
		const todayId = workoutIds.get('today')!;
		await expect
			.poll(
				async () =>
					(
						await readRow(
							'today workout',
							getAdminClient().from('plan_workouts').select('completed_run_id').eq('id', todayId).single()
						)
					).completed_run_id
			)
			.not.toBeNull();

		const page = await openHome();
		await expect(page.getByTestId('plan-hero-done')).toHaveText('Completed', { timeout: 15_000 });
		await page.goto(`/plans/${planId}/workouts/${todayId}`);
		await expect(page.getByTestId('workout-detail-done')).toHaveText('Completed', { timeout: 15_000 });
	});
});
