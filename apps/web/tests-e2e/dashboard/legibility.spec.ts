import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun, setUserSetting } from '../fixtures/simulate';

/**
 * /dashboard says what its numbers mean (#902 section 1).
 *
 * Each assertion is one defect the screenshot pass found on this page:
 *  1.1 the readiness breakdown and the TSB tile both said "Form (TSB)" over
 *      two different numbers;
 *  1.3 the intensity card named heart-rate zones by bare digit when
 *      Preferences already names them;
 *  1.4 the distance chart was titled with an imperial word over metric bars;
 *  1.5 a lift's volume lost its unit;
 *  1.6 an empty week read as a measurement ("0 m", "--") beside a lifetime
 *      total.
 *
 * One runner with a single run ten days ago — always last week or earlier,
 * so this week is empty whatever day the suite runs — plus zones, a heart
 * rate on that run, and one weighted lift.
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

test.describe('dashboard legibility', () => {
	let runner: SagaUser;
	let workoutId: string | null = null;

	test.beforeAll(async () => {
		[runner] = await createSagaUsers(1, { displayNames: ['Legibility Runner'] });
		await setUserSetting(runner.id, 'hr_zones', { z1: 130, z2: 145, z3: 160, z4: 175, z5: 195 });
		await insertRun({
			user_id: runner.id,
			started_at: new Date(Date.now() - 10 * 86_400_000).toISOString(),
			distance_m: 10_000,
			duration_s: 3_000,
			source: 'app',
			metadata: { avg_bpm: 140 },
		});
		const admin = getAdminClient();
		const now = new Date().toISOString();
		const { data: w } = await admin
			.from('gym_workouts')
			.insert({ user_id: runner.id, title: 'Legibility lift', started_at: now, last_modified_at: now })
			.select('id')
			.single();
		workoutId = (w?.id as string) ?? null;
		await admin.from('gym_sets').insert({
			workout_id: workoutId,
			exercise_name: 'Bench press',
			set_index: 0,
			reps: 8,
			weight_kg: 60,
		});
	});

	test.afterAll(async () => {
		if (workoutId) await getAdminClient().from('gym_workouts').delete().eq('id', workoutId);
		if (runner) await deleteSagaUsers([runner]);
	});

	test('every number on the page says what it is', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: runner.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await page.goto('/dashboard');
			await expect(page.locator('.stat-grid')).toBeVisible({ timeout: 15_000 });

			// 1.6 — an empty week in words, not a zero that reads as data.
			const tile = (label: RegExp) =>
				page
					.locator('.stat-grid .stat-card')
					.filter({ has: page.locator('.stat-label', { hasText: label }) })
					.first();
			for (const label of [/^This Week$/, /This Week Pace/]) {
				await expect(tile(label).locator('.stat-value')).toHaveText('No runs yet');
			}
			await expect(tile(/^This Week$/)).not.toContainText('0 m');
			await expect(page.locator('.stat-grid')).not.toContainText('--');

			// 1.1 — the readiness breakdown no longer borrows the TSB tile's name.
			const contribs = page.locator('.readiness-contribs');
			await expect(contribs).toContainText('Training balance');
			await expect(contribs).not.toContainText('TSB');

			// 1.3 — zones by the names Preferences gives them.
			const zoneNames = page.locator('.zone-name');
			await expect(zoneNames).toHaveText([
				'Z1 (recovery)',
				'Z2 (easy)',
				'Z3 (tempo)',
				'Z4 (threshold)',
				'Z5 (max)',
			]);

			// 1.4 — a unit-neutral title over the chart.
			await expect(page.getByRole('heading', { level: 2, name: 'Distance', exact: true })).toBeVisible();
			await expect(page.getByRole('heading', { level: 2, name: 'Mileage' })).toHaveCount(0);

			// 1.5 — 8 × 60 kg carries its unit, as it does on /gym.
			const lifts = page.locator('section.card-elevated', { hasText: 'Recent lifts' });
			await expect(lifts.locator('.lift-volume')).toHaveText(/^480\s?kg$/);
		} finally {
			await ctx.close();
		}
	});
});
