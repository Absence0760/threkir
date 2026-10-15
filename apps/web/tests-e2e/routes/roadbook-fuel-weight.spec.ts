import { expect, test } from '../fixtures/test';

import { noonOnBrowserDay } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { deleteRoute } from '../fixtures/simulate';

/**
 * The roadbook's weight-based fluid toggle (decisions § 1976), the roadbook
 * twin of nutrition/fuel-weight.spec.ts. Saga users, because planting
 * health-data consent on the shared seed user would change every other spec's
 * surfaces.
 */
test.describe('/routes/[id]/roadbook — fluid from body weight', () => {
	test.describe.configure({ timeout: 120_000 });

	const admin = getAdminClient();
	let user: SagaUser | null = null;
	let routeId: string | null = null;

	async function plant(weightKg: number): Promise<SagaUser> {
		const [saga] = await createSagaUsers(1, { displayNames: ['Roadbook Weight Saga'] });
		user = saga;
		const { error: consentErr } = await admin
			.from('user_profiles')
			.update({ health_data_consent_at: new Date().toISOString() })
			.eq('id', saga.id);
		if (consentErr) throw consentErr;
		const { error: weightErr } = await admin
			.from('body_metrics')
			.insert({ user_id: saga.id, weight_kg: weightKg, recorded_at: noonOnBrowserDay(-1) });
		if (weightErr) throw weightErr;

		routeId = crypto.randomUUID();
		const waypoints = [];
		for (let i = 0; i <= 18; i++) waypoints.push({ lat: 51.5 + i * 0.001, lng: -0.12, ele: 0 });
		const { error: routeErr } = await admin.from('routes').insert({
			id: routeId,
			user_id: saga.id,
			name: 'E2E Roadbook Weight Course',
			waypoints,
			distance_m: 2000,
			is_public: false
		});
		if (routeErr) throw routeErr;
		const { error: markerErr } = await admin.from('route_markers').insert({
			route_id: routeId,
			user_id: saga.id,
			kind: 'aid_station',
			label: 'Aid 1',
			lat: 51.5 + 9 * 0.001,
			lng: -0.12,
			meta: { services: ['water', 'food'] }
		});
		if (markerErr) throw markerErr;
		return saga;
	}

	test.afterEach(async () => {
		if (routeId) {
			try {
				await deleteRoute(routeId);
			} catch (_) {
				/* the user delete cascades it */
			}
			routeId = null;
		}
		if (user) await deleteSagaUsers([user]);
		user = null;
	});

	test('with consent and a weight, the toggle scales per-leg fluid and survives a reload', async ({
		browser
	}) => {
		const saga = await plant(90);
		const ctx = await browser.newContext({ storageState: saga.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto(`/routes/${routeId}/roadbook?goal=7200&fuel=1`);
			const toggle = page.getByTestId('roadbook-fuel-weight');
			await expect(toggle).toBeEnabled();
			await expect(toggle).toHaveAttribute('aria-pressed', 'false');
			await expect(page.getByTestId('roadbook-weight-hint')).toContainText('Scales the fluid rate');

			const aidFluid = page.locator('[data-testid="fuel-carbs"] + td').nth(1);
			await expect(aidFluid).toContainText('ml');
			const flatMl = parseInt((await aidFluid.textContent()) ?? '', 10);
			expect(flatMl).toBeGreaterThan(0);

			await toggle.click();
			await expect(page).toHaveURL(/bw=1/);
			await expect(toggle).toHaveAttribute('aria-pressed', 'true');
			// 500 × 90 / 70 = 642.9 → 650 ml/h.
			await expect(page.getByTestId('roadbook-weight-hint')).toHaveText(
				'Fluid: 650 ml per hour from your body weight.'
			);
			await expect(async () => {
				const weightMl = parseInt((await aidFluid.textContent()) ?? '', 10);
				expect(weightMl).toBeGreaterThan(flatMl);
			}).toPass();

			await page.reload();
			await expect(page.getByTestId('roadbook-fuel-weight')).toHaveAttribute('aria-pressed', 'true');
			await expect(page.getByTestId('roadbook-weight-hint')).toHaveText(
				'Fluid: 650 ml per hour from your body weight.'
			);

			await page.getByTestId('roadbook-fuel-weight').click();
			await expect(page).not.toHaveURL(/bw=1/);
			await expect(page.getByTestId('roadbook-weight-hint')).toContainText('Scales the fluid rate');
		} finally {
			await ctx.close();
		}
	});
});
