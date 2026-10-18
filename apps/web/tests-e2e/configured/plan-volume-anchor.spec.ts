import type { BrowserContext, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { browserDate, browserDayStart, noonOnBrowserDay } from '../fixtures/dates';
import { readMaybeRow, readRow, readRows } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { deletePlan, insertRun } from '../fixtures/simulate';

/**
 * The comeback ramp (decisions § 2090, § 2162): a week well under plan, or a
 * return from weeks away, offers the weeks ahead rebuilt from the volume the
 * runner actually ran, through the plan's own re-plan preview. It ships behind
 * `PUBLIC_ADAPTIVE_FITNESS_GATE`, which this lane's dev server turns on
 * (playwright.configured.config.ts); the gate-off half, where none of this
 * appears, is pinned in plans/plan-nudges.spec.ts. The rules are unit-tested
 * on both sides (plan_volume_anchor).
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

test.describe('The comeback ramp, gate on', () => {
	test.describe.configure({ mode: 'serial', timeout: 90_000 });

	test.beforeAll(async ({}, testInfo) => {
		[user] = await createSagaUsers(1, {
			displayNames: ['Nudge Runner'],
			baseURL: testInfo.project.use.baseURL
		});
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

	test('a week well under plan offers to build back from it; Review opens the anchored preview and applying caps the weeks ahead', async () => {
		const { planId, workoutIds } = await plantPlan('e2e nudge anchor', [
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
		const card = page.getByTestId('plan-nudge');
		await expect(card).toBeVisible({ timeout: 15_000 });
		await expect(card).toHaveAttribute('data-kind', 'anchor_under');
		await expect(card).toContainText('Last week came in short');

		await card.getByRole('button', { name: 'Review the changes' }).click();
		await expect(page).toHaveURL(new RegExp(`/plans/${planId}`));
		const preview = page.locator('.replan-preview');
		await expect(preview).toBeVisible({ timeout: 15_000 });
		await expect(preview.getByTestId('replan-anchor-note')).toContainText('came in at 10.0 km');
		// Week 3 may ask for 11 km: its 8 + 20 km scale by 11/28 to the 100 m.
		await expect(preview).toContainText('8.0 km → 3.1 km');
		await expect(preview).toContainText('20.0 km → 7.8 km');
		await expect.poll(dismissed).toEqual([`${planId}:anchor_under:2`]);

		await preview.getByRole('button', { name: 'Apply changes' }).click();
		const target = async (key: string) =>
			(
				await readRow(
					key,
					getAdminClient().from('plan_workouts').select('target_distance_m').eq('id', workoutIds.get(key)!).single()
				)
			).target_distance_m;
		await expect.poll(() => target('easy3')).toBe(3_100);
		await expect.poll(() => target('long3')).toBe(7_800);
		// Week 4 climbs 10% on week 3's 10.9 km: 11.99 km over 28 km.
		await expect.poll(() => target('long4')).toBe(8_500);

		await page.goto('/dashboard');
		await expect(page.locator('.plan-hero')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('plan-nudge')).toHaveCount(0);
	});

	test('resuming a plan offers the weeks ahead re-anchored to the last week run, and nothing changes until Apply', async () => {
		const { planId, workoutIds } = await plantPlan(
			'e2e nudge resume',
			[{ volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }, { volume: 28_000 }],
			{ status: 'paused' }
		);
		const { error } = await getAdminClient()
			.from('training_plans')
			.update({ paused_at: browserDayStart(day(1, 1)) })
			.eq('id', planId);
		if (error) throw error;
		await run(day(0, 6), 28_000);
		await run(day(1, 0), 8_000);

		const page = await ctx!.newPage();
		await page.goto(`/plans/${planId}?resume=1`);
		await expect(page.getByText(/move back 2 weeks/)).toBeVisible({ timeout: 15_000 });
		await page.getByRole('button', { name: 'Apply' }).click();
		await expect(page.getByText('Plan resumed and pushed back 2 weeks.')).toBeVisible();

		const preview = page.locator('.replan-preview');
		await expect(preview).toBeVisible({ timeout: 15_000 });
		await expect(preview.getByTestId('replan-anchor-note')).toContainText('came in at 8.0 km');
		// The first week back may ask for 8.8 km: the long run scales to 6.2 km
		// and the easy run holds at the 3 km floor.
		await expect(preview).toContainText('20.0 km → 6.2 km');
		const target = async (key: string) =>
			(
				await readRow(
					key,
					getAdminClient().from('plan_workouts').select('target_distance_m').eq('id', workoutIds.get(key)!).single()
				)
			).target_distance_m;
		expect(await target('long2')).toBe(20_000);

		await preview.getByRole('button', { name: 'Apply changes' }).click();
		await expect.poll(() => target('long2')).toBe(6_200);
		await expect.poll(() => target('easy2')).toBe(3_000);
	});
});
