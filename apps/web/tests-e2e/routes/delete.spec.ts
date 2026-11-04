import { expect, test } from '../fixtures/test';

import { getAdminClient, resetRateLimit } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';
import { deleteRaceListing, deleteRoute, insertRaceListing, insertRoute } from '../fixtures/simulate';

/**
 * /routes/[id] — the owner's Delete (issue #1286).
 *
 * Deleting a route cascades its photos, markers and other runners' reviews,
 * bookmarks and segments, so it takes a ConfirmDialog and no undo. The
 * confirm names what depends on the route, from `route_delete_impact`,
 * including the two things the owner's own session cannot read: another
 * runner's bookmark and a race listing using it as its course.
 */

const WAYPOINTS = [
	{ lat: -37.82, lng: 144.97 },
	{ lat: -37.816, lng: 144.974 },
	{ lat: -37.812, lng: 144.978 },
];

async function routeExists(id: string): Promise<boolean> {
	const { data, error } = await getAdminClient().from('routes').select('id').eq('id', id).maybeSingle();
	if (error) throw new Error(`routeExists: ${error.message}`);
	return data !== null;
}

test.describe('/routes/[id] delete — owner', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let routeId = '';
	let listingId = '';
	let routeName = '';

	test.beforeEach(async () => {
		await resetRateLimit(USER_A.id, 'create_route');
		routeName = `E2E delete route ${Date.now()}`;
		routeId = await insertRoute({
			user_id: USER_A.id,
			name: routeName,
			waypoints: WAYPOINTS,
			distance_m: 1200,
			is_public: true,
		});
		const admin = getAdminClient();
		const { error } = await admin.from('saved_routes').insert({ user_id: USER_B.id, route_id: routeId });
		if (error) throw new Error(`saved_routes seed: ${error.message}`);
		listingId = await insertRaceListing({
			provider: 'runsignup',
			provider_race_id: `e2e-delete-${Date.now()}`,
			name: 'E2E Delete Course 1K',
			race_date: '2036-06-01',
			distance_m: 1200,
		});
		const { error: linkError } = await admin.from('race_listings').update({ route_id: routeId }).eq('id', listingId);
		if (linkError) throw new Error(`race listing link: ${linkError.message}`);
	});

	test.afterEach(async () => {
		if (routeId && (await routeExists(routeId))) await deleteRoute(routeId);
		if (listingId) await deleteRaceListing(listingId);
	});

	test('the confirm names what depends on the route; cancel keeps it, confirm deletes and returns to the list', async ({
		page,
	}) => {
		await page.goto(`/routes/${routeId}`);
		await expect(page.getByRole('heading', { name: routeName, level: 1 })).toBeVisible({ timeout: 10_000 });

		const deleteBtn = page.getByTestId('route-delete-btn');
		await deleteBtn.click();
		const dialog = page.getByTestId('route-delete-confirm-dialog');
		await expect(dialog).toBeVisible();
		await expect(dialog).toContainText('Delete this route?');
		await expect(dialog).toContainText('It is public');
		await expect(dialog).toContainText('1 race listing uses it as its course');
		await expect(dialog).toContainText('1 other runner has saved it.');

		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(dialog).toBeHidden();
		expect(await routeExists(routeId)).toBe(true);

		await deleteBtn.click();
		await expect(dialog).toBeVisible();
		await dialog.getByRole('button', { name: 'Delete route' }).click();

		await expect(page).toHaveURL(/\/routes$/, { timeout: 10_000 });
		await expect(page.locator('.toast').filter({ hasText: 'Route deleted' })).toBeVisible();
		await expect.poll(() => routeExists(routeId)).toBe(false);

		const { data: listing, error: listingError } = await getAdminClient()
			.from('race_listings')
			.select('route_id, is_verified')
			.eq('id', listingId)
			.single();
		expect(listingError).toBeNull();
		expect(listing).toEqual({ route_id: null, is_verified: true });
	});

	test('a failed delete stays on the page, says why, and keeps the route', async ({ page, mockRoute }) => {
		await mockRoute(page, '**/rest/v1/routes?*', (route) =>
			route.request().method() === 'DELETE'
				? route.fulfill({
						status: 500,
						contentType: 'application/json',
						body: JSON.stringify({ message: 'injected delete failure', code: 'XX000' }),
					})
				: route.fallback(),
		);
		await page.goto(`/routes/${routeId}`);
		await expect(page.getByRole('heading', { name: routeName, level: 1 })).toBeVisible({ timeout: 10_000 });

		await page.getByTestId('route-delete-btn').click();
		const dialog = page.getByTestId('route-delete-confirm-dialog');
		await dialog.getByRole('button', { name: 'Delete route' }).click();

		await expect(page.locator('.toast.toast-error')).toContainText('Could not delete the route');
		await expect(dialog).toBeHidden();
		await expect(page).toHaveURL(new RegExp(`/routes/${routeId}$`));
		expect(await routeExists(routeId)).toBe(true);
	});

	test('a double click on the confirm deletes once, with one toast and one navigation', async ({
		page,
		mockRoute,
	}) => {
		let deletes = 0;
		let release = () => {};
		const held = new Promise<void>((resolve) => (release = resolve));
		await mockRoute(page, '**/rest/v1/routes?*', async (route) => {
			if (route.request().method() !== 'DELETE') return route.fallback();
			deletes++;
			await held;
			return route.fallback();
		});
		await page.goto(`/routes/${routeId}`);
		await expect(page.getByRole('heading', { name: routeName, level: 1 })).toBeVisible({ timeout: 10_000 });

		await page.getByTestId('route-delete-btn').click();
		const dialog = page.getByTestId('route-delete-confirm-dialog');
		const confirm = dialog.getByRole('button', { name: 'Delete route' });
		await confirm.dblclick();
		await expect(confirm).toBeDisabled();
		await page.keyboard.press('Enter');
		release();

		await expect(page).toHaveURL(/\/routes$/, { timeout: 10_000 });
		await expect(page.locator('.toast').filter({ hasText: 'Route deleted' })).toHaveCount(1);
		await expect.poll(() => routeExists(routeId)).toBe(false);
		expect(deletes).toBe(1);
	});

	test('a failed impact count still opens the confirm, and says the count is missing', async ({ page, mockRoute }) => {
		await mockRoute(page, '**/rest/v1/rpc/route_delete_impact*', (route) =>
			route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"injected"}' }),
		);
		await page.goto(`/routes/${routeId}`);
		await expect(page.getByRole('heading', { name: routeName, level: 1 })).toBeVisible({ timeout: 10_000 });

		await page.getByTestId('route-delete-btn').click();
		const dialog = page.getByTestId('route-delete-confirm-dialog');
		await expect(dialog).toContainText("We couldn't check what else uses this route.");
		await expect(dialog).not.toContainText('other runner has saved it');
	});
});

test.describe('/routes/[id] delete — another runner', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let routeId = '';
	let routeName = '';

	test.beforeEach(async () => {
		routeName = `E2E not-yours route ${Date.now()}`;
		routeId = await insertRoute({
			user_id: USER_A.id,
			name: routeName,
			waypoints: WAYPOINTS,
			distance_m: 1200,
			is_public: true,
		});
	});

	test.afterEach(async () => {
		if (routeId) await deleteRoute(routeId);
	});

	test('a public route someone else owns offers no Delete', async ({ page }) => {
		await page.goto(`/routes/${routeId}`);
		await expect(page.getByRole('heading', { name: routeName, level: 1 })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByRole('button', { name: 'Report this route' })).toBeVisible();
		await expect(page.getByTestId('route-delete-btn')).toHaveCount(0);
	});
});
