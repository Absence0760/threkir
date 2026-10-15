import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * /nutrition/fuel — the route-less fuelling plan the Coach's fuelling handoff
 * links to (decisions § 1975). The link is model output, so every parameter is
 * validated on arrival: an in-range value is used and labelled as set on the
 * page, an out-of-range one is dropped and the runner's own rate (or the app
 * default) is used instead. PUBLIC_COACH_FUEL_ENABLED is on in .env.development.
 */

test.describe('/nutrition/fuel signed out', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('a link with a duration and no rates plans from the app defaults', async ({ page }) => {
		await page.goto('/nutrition/fuel?duration=3600');
		await expect(page.getByRole('heading', { level: 1, name: 'Fuelling plan' })).toBeVisible();
		// One hour at 60 g/h and 500 ml/h: 60 g of carbohydrate, three 25 g gels.
		await expect(page.getByTestId('fuel-total-carbs')).toHaveText('60 g');
		await expect(page.getByTestId('fuel-gels')).toHaveText('3');
		await expect(page.getByTestId('fuel-total-fluid')).toHaveText('500 ml');
		await expect(page.getByTestId('fuel-carbs-source')).toHaveText('App default');
		await expect(page.getByTestId('fuel-fluid-source')).toHaveText('App default');
	});
});

test.describe('/nutrition/fuel', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('rates the link carries are used, labelled, and the heat toggle scales fluid only', async ({ page }) => {
		await page.goto('/nutrition/fuel?duration=9000&carbs=60&fluid=500');
		// 2.5 h: 150 g → six gels; 1250 ml.
		await expect(page.getByTestId('fuel-total-carbs')).toHaveText('150 g');
		await expect(page.getByTestId('fuel-gels')).toHaveText('6');
		await expect(page.getByTestId('fuel-total-fluid')).toHaveText('1250 ml');
		await expect(page.getByTestId('fuel-carbs-source')).toHaveText('Set on this page');
		await expect(page.getByTestId('fuel-duration')).toHaveValue('2:30');

		await page.getByTestId('fuel-heat').check();
		await expect(page).toHaveURL(/heat=1/);
		await expect(page.getByTestId('fuel-total-fluid')).toHaveText('1875 ml');
		await expect(page.getByTestId('fuel-total-carbs')).toHaveText('150 g');
	});

	test('an out-of-range rate in the link is dropped, never clamped or used', async ({ page }) => {
		await page.goto('/nutrition/fuel?duration=3600&carbs=900&fluid=9000');
		await expect(page.getByTestId('fuel-totals')).toBeVisible();
		await expect(page.getByTestId('fuel-carbs-source')).not.toHaveText('Set on this page');
		await expect(page.getByTestId('fuel-fluid-source')).not.toHaveText('Set on this page');
		await expect(page.getByTestId('fuel-total-carbs')).not.toHaveText('900 g');
		await expect(page.getByTestId('fuel-total-fluid')).not.toHaveText('9000 ml');
	});

	test('a missing or out-of-range duration asks for one instead of planning', async ({ page }) => {
		await page.goto('/nutrition/fuel?duration=30');
		await expect(page.getByTestId('fuel-needs-duration')).toBeVisible();
		await expect(page.getByTestId('fuel-totals')).toHaveCount(0);

		await page.getByTestId('fuel-duration').fill('1:00');
		await page.getByTestId('fuel-duration').blur();
		await expect(page).toHaveURL(/duration=3600/);
		await expect(page.getByTestId('fuel-totals')).toBeVisible();
	});
});
