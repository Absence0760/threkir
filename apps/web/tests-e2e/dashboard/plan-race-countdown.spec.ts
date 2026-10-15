import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers } from '../fixtures/saga-users';

/**
 * The dashboard plan hero's race-relation chip reads `planRaceCountdown`
 * (plan_week.ts), the helper mobile's NextRaceCard shares. page.spec.ts only
 * matches /Race in \d+ day/ against the seed plan; this pins the exact count
 * for each state against dates set relative to the browser's day. A saga user,
 * so the one-active-plan index never meets the seed plan.
 */
test.describe('/dashboard — plan race countdown', () => {
	test.describe.configure({ timeout: 120_000 });

	const CASES: { name: string; start: number; end: number; relation: string }[] = [
		{ name: 'race twelve days out', start: -3, end: 12, relation: 'Race in 12 days' },
		{ name: 'race tomorrow', start: -20, end: 1, relation: 'Race tomorrow' },
		{ name: 'race today', start: -20, end: 0, relation: 'Race day' },
		{ name: 'plan not started', start: 4, end: 60, relation: 'Starts in 4 days' }
	];

	test('the relation chip counts whole days to the start or the race', async ({ browser }) => {
		const [runner] = await createSagaUsers(1, { displayNames: ['Countdown Runner'] });
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const ctx = await browser.newContext({ storageState: runner.storageStatePath });
		try {
			const { error } = await admin.from('training_plans').insert({
				id: planId,
				user_id: runner.id,
				name: 'e2e countdown',
				goal_event: 'distance_half',
				goal_distance_m: 21097.5,
				goal_time_seconds: null,
				start_date: browserDate(CASES[0].start),
				end_date: browserDate(CASES[0].end),
				status: 'active',
				days_per_week: 4
			});
			if (error) throw error;
			const { error: weekErr } = await admin.from('plan_weeks').insert({
				id: crypto.randomUUID(),
				plan_id: planId,
				week_index: 0,
				phase: 'build',
				target_volume_m: 30_000
			});
			if (weekErr) throw weekErr;

			const page = await ctx.newPage();
			for (const c of CASES) {
				const { error: e } = await admin
					.from('training_plans')
					.update({ start_date: browserDate(c.start), end_date: browserDate(c.end) })
					.eq('id', planId);
				if (e) throw e;
				await page.goto('/dashboard');
				const relation = page.locator('.plan-hero .plan-hero-relation');
				await expect(relation, c.name).toHaveText(c.relation, { timeout: 15_000 });
				if (c.end === 0) await expect(relation).toHaveClass(/race-today/);
				else await expect(relation).not.toHaveClass(/race-today/);
			}
		} finally {
			await ctx.close();
			await admin.from('training_plans').delete().eq('id', planId);
			await deleteSagaUsers([runner]);
		}
	});
});
