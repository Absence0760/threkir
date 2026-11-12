import { expect, test } from '../fixtures/test';

import { expandTrainingLoad } from '../fixtures/dashboard';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun, setUserSetting } from '../fixtures/simulate';

/**
 * The training-load chart says its heart-rate load is less reliable when the
 * runner has said a medication affects their heart rate (decisions § 2092).
 * The label is behind the fail-closed server hr_prescription gate, which
 * seed.sql opens; its off state (no label whatever the setting) is
 * pinned by src/lib/training/hr_prescription_gate.test.ts, the same split
 * every default-off Art 9 gate uses. Saga users, because the flag needs the
 * health-data consent and planting it on a shared seed user would change
 * every other spec's surfaces.
 */

const LABEL =
	'Less reliable: you said your heart rate is affected by medication, which makes the heart-rate load read low.';

test.describe('dashboard training load — medication-affected heart rate', () => {
	test.describe.configure({ timeout: 90_000 });

	let medicated: SagaUser;
	let unflagged: SagaUser;

	test.beforeAll(async () => {
		[medicated, unflagged] = await createSagaUsers(2, {
			displayNames: ['Medicated HR Runner', 'Unflagged HR Runner'],
		});
		const admin = getAdminClient();
		for (const user of [medicated, unflagged]) {
			const { error } = await admin
				.from('user_profiles')
				.update({ health_data_consent_at: new Date().toISOString() })
				.eq('id', user.id);
			if (error) throw error;
			await setUserSetting(user.id, 'resting_hr_bpm', 50);
			await setUserSetting(user.id, 'max_hr_bpm', 180);
			for (const [daysAgo, distance_m, duration_s, avg_bpm] of [
				[2, 10_000, 3_000, 145],
				[4, 6_000, 1_800, 140],
				[6, 12_000, 3_700, 150],
			] as const) {
				await insertRun({
					user_id: user.id,
					started_at: new Date(Date.now() - daysAgo * 86_400_000).toISOString(),
					distance_m,
					duration_s,
					source: 'app',
					metadata: { avg_bpm },
				});
			}
		}
		await setUserSetting(medicated.id, 'hr_medication_affected', true);
	});

	test.afterAll(async () => {
		await deleteSagaUsers([medicated, unflagged].filter(Boolean));
	});

	async function trainingLoadHeader(user: SagaUser, browser: import('@playwright/test').Browser) {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		await page.goto('/dashboard');
		await expandTrainingLoad(page);
		const chart = page.locator('.training-load');
		await expect(chart).toBeVisible({ timeout: 15_000 });
		await expect(chart.locator('header p.hint').first()).toContainText('heart-rate-based');
		return { ctx, chart };
	}

	test('a runner who flagged the medication sees the load marked less reliable', async ({ browser }) => {
		const { ctx, chart } = await trainingLoadHeader(medicated, browser);
		try {
			await expect(chart.getByTestId('training-load-low-confidence')).toHaveText(LABEL);
		} finally {
			await ctx.close();
		}
	});

	test('the same heart-rate load without the flag carries no label', async ({ browser }) => {
		const { ctx, chart } = await trainingLoadHeader(unflagged, browser);
		try {
			await expect(chart.getByTestId('training-load-low-confidence')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
