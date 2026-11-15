import { expect, test } from '../fixtures/test';

import { noonOnBrowserDay } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * The fuelling plan's weight-based fluid rate (decisions § 1976). Body weight
 * is Art 9 data, so the rate is offered only when a weight is on record AND the
 * health-data consent is; without either the toggle is disabled with the
 * reason, and the flat rate stands. Saga users, because planting consent on
 * the shared seed user would change every other spec's surfaces. The toggle is
 * behind the fail-closed PUBLIC_WEIGHT_FLUID_ENABLED, which is on in
 * .env.development; its off state (no weight read, no toggle) is pinned by
 * src/lib/nutrition/weight_fluid_flag.test.ts.
 */
test.describe('/nutrition/fuel — fluid from body weight', () => {
	test.describe.configure({ timeout: 120_000 });

	const admin = getAdminClient();
	let user: SagaUser;

	async function plant(weightKg: number) {
		[user] = await createSagaUsers(1, { displayNames: ['Fuel Weight Saga'] });
		const { error: consentErr } = await admin
			.from('user_profiles')
			.update({ health_data_consent_at: new Date().toISOString() })
			.eq('id', user.id);
		if (consentErr) throw consentErr;
		const { error } = await admin
			.from('body_metrics')
			.insert({ user_id: user.id, weight_kg: weightKg, recorded_at: noonOnBrowserDay(-1) });
		if (error) throw error;
	}

	test.afterEach(async () => {
		if (user) await deleteSagaUsers([user]);
	});

	test('with consent and a weight, opting in scales fluid by weight and heat still multiplies it', async ({
		browser,
	}) => {
		await plant(90);
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto('/nutrition/fuel?duration=3600');
			const toggle = page.getByTestId('fuel-weight');
			await expect(toggle).toBeEnabled();
			await expect(page.getByTestId('fuel-total-fluid')).toHaveText('500 ml');

			await toggle.check();
			await expect(page).toHaveURL(/bw=1/);
			// 500 × 90 / 70 = 642.9 → 650 ml/h.
			await expect(page.getByTestId('fuel-total-fluid')).toHaveText('650 ml');
			await expect(page.getByTestId('fuel-fluid-source')).toHaveText('From your body weight');

			await page.getByTestId('fuel-heat').check();
			await expect(page.getByTestId('fuel-total-fluid')).toHaveText('975 ml');
		} finally {
			await ctx.close();
		}
	});

	// The database holds no weight without consent (decisions § 2547): a
	// withdrawal erases the series, and a new one is refused. So the case to
	// pin is the withdrawal, followed by a link that still asks for the rate.
	test('after consent is withdrawn no weight is used, even with ?bw=1 in the link', async ({ browser }) => {
		await plant(90);
		const { error: withdrawErr } = await admin
			.from('user_profiles')
			.update({ health_data_consent_at: null })
			.eq('id', user.id);
		if (withdrawErr) throw withdrawErr;
		const { count, error: countErr } = await admin
			.from('body_metrics')
			.select('id', { count: 'exact', head: true })
			.eq('user_id', user.id);
		if (countErr) throw countErr;
		expect(count, 'the withdrawal erased the weight series').toBe(0);
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto('/nutrition/fuel?duration=3600&bw=1');
			await expect(page.getByTestId('fuel-weight')).toBeDisabled();
			await expect(page.getByTestId('fuel-weight-hint')).toContainText('health-data consent');
			await expect(page.getByTestId('fuel-total-fluid')).toHaveText('500 ml');
			await expect(page.getByTestId('fuel-fluid-source')).not.toHaveText('From your body weight');
		} finally {
			await ctx.close();
		}
	});
});
