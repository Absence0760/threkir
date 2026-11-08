import { expect, test } from '../fixtures/test';

import { resetRateLimit } from '../fixtures/local-supabase';
import { deleteRoute } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Add run → "Build one" → route builder → back with the route selected
 * (issue #1300 § 3). The run editor's route picker used to show "No route"
 * with nothing to act on when the user had no saved routes.
 *
 * The seeded user's route list is shared with every spec that plants a
 * route, so the empty state is produced by answering the editor's first
 * route reads with no rows, then letting the real reads through once the
 * route exists.
 */

test.describe('/runs/new — build a route from the empty picker', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let plantedRouteId: string | null = null;

	test.beforeEach(async () => {
		await resetRateLimit(USER_A.id, 'create_route');
	});

	test.afterEach(async () => {
		if (plantedRouteId) {
			await deleteRoute(plantedRouteId);
			plantedRouteId = null;
		}
		await resetRateLimit(USER_A.id, 'create_route');
	});

	test('the empty picker links to the builder, which returns the saved route preselected', async ({
		page
	}) => {
		const emptyList = async (route: import('@playwright/test').Route) => {
			if (route.request().method() !== 'GET') return route.fallback();
			await route.fulfill({ status: 200, contentType: 'application/json', body: '[]' });
		};
		await page.route('**/rest/v1/routes?**', emptyList);
		await page.route('**/rest/v1/saved_routes?**', emptyList);

		await page.goto('/runs/new');
		const build = page.getByTestId('run-editor-build-route');
		await expect(build).toBeVisible({ timeout: 10_000 });
		await expect(build).toHaveText('Build one');
		await expect(build).toHaveAttribute('href', '/routes/new?return=%2Fruns%2Fnew');

		await page.unroute('**/rest/v1/routes?**');
		await page.unroute('**/rest/v1/saved_routes?**');

		await build.click();
		await page.waitForURL(/\/routes\/new\?return=%2Fruns%2Fnew$/);
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });

		const name = `e2e build-from-add-run ${Date.now()}`;
		const saveBtn = page.getByRole('button', { name: /Save Route/ });
		await saveBtn.evaluate((el: HTMLButtonElement) => (el.disabled = false));
		await saveBtn.click();
		const modal = page.locator('.modal', { hasText: 'Save route' });
		await expect(modal).toBeVisible({ timeout: 5_000 });
		await modal.getByPlaceholder('My Route').fill(name);
		const submit = modal.getByRole('button', { name: /Save route/ });
		await submit.evaluate((el: HTMLButtonElement) => (el.disabled = false));
		await submit.click();

		await page.waitForURL(/\/runs\/new\?route=[0-9a-f-]+$/, { timeout: 15_000 });
		plantedRouteId = new URL(page.url()).searchParams.get('route');
		expect(plantedRouteId).not.toBeNull();

		const picker = page.getByLabel('Route (optional)');
		await expect(picker).toHaveValue(plantedRouteId!, { timeout: 10_000 });
		await expect(picker.locator('option:checked')).toHaveText(name);
		await expect(page.getByTestId('run-editor-build-route')).toHaveCount(0);
	});

	test('an off-origin return target is ignored and the builder opens the saved route', async ({
		page
	}) => {
		await page.goto('/routes/new?return=%2F%2Fevil.example%2Fruns%2Fnew');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });

		const saveBtn = page.getByRole('button', { name: /Save Route/ });
		await saveBtn.evaluate((el: HTMLButtonElement) => (el.disabled = false));
		await saveBtn.click();
		const modal = page.locator('.modal', { hasText: 'Save route' });
		await expect(modal).toBeVisible({ timeout: 5_000 });
		await modal.getByPlaceholder('My Route').fill(`e2e evil return ${Date.now()}`);
		const submit = modal.getByRole('button', { name: /Save route/ });
		await submit.evaluate((el: HTMLButtonElement) => (el.disabled = false));
		await submit.click();

		await page.waitForURL(/\/routes\/[0-9a-f-]+$/, { timeout: 15_000 });
		plantedRouteId = page.url().match(/\/routes\/([0-9a-f-]+)$/)![1];
		expect(page.url()).not.toContain('evil.example');
	});
});
