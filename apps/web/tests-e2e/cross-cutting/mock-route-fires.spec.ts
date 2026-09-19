import { expect, test } from '../fixtures/mock-route';

/**
 * The instrument's own proof. `mockRoute` only earns its keep if a mock that
 * never matches turns the test RED, and a guard nobody has seen fail is not a
 * guard — so the two failing shapes are asserted here through `test.fail()`,
 * which passes exactly when the body (or its fixture teardown) fails.
 *
 * The lane is unauthenticated on purpose: /login renders without a session and
 * without touching any of the endpoints these patterns name.
 */
test.describe('mockRoute reports a mock that did not fire', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('a pattern nothing requests fails the test', async ({ page, mockRoute }) => {
		test.fail();
		await mockRoute(page, '**/no-endpoint-answers-this/**', (route) => route.abort());
		await page.goto('/login');
	});

	test('a `neverFires` mock that does fire fails the test', async ({ page, mockRoute }) => {
		test.fail();
		await mockRoute(page, '**/login**', (route) => route.continue(), {
			neverFires: 'deliberately wrong: /login is exactly what this case navigates to'
		});
		await page.goto('/login');
	});

	test('a mock that fires passes, and its handler is the one that answered', async ({
		page,
		mockRoute
	}) => {
		await mockRoute(page, '**/login**', (route) =>
			route.fulfill({ status: 200, contentType: 'text/html', body: '<h1>stubbed</h1>' })
		);
		await page.goto('/login');
		await expect(page.getByRole('heading', { name: 'stubbed' })).toBeVisible();
	});

	test('a silence declared for a pattern nothing registered fails the test', async ({
		page,
		mockRoute
	}) => {
		test.fail();
		mockRoute.neverFires('**/nothing-registered-this/**', 'deliberately stale: no mock uses it');
		await page.goto('/login');
	});

	test('declaring a registered mock silent is accepted', async ({ page, mockRoute }) => {
		await mockRoute(page, '**/no-endpoint-answers-this/**', (route) => route.abort());
		mockRoute.neverFires(
			'**/no-endpoint-answers-this/**',
			'/login requests nothing under this path — the point of the case'
		);
		await page.goto('/login');
		await expect(page).toHaveURL(/\/login/);
	});

	test('a `neverFires` mock that stays silent passes', async ({ page, mockRoute }) => {
		await mockRoute(page, '**/no-endpoint-answers-this/**', (route) => route.abort(), {
			neverFires: '/login requests nothing under this path — the point of the case'
		});
		await page.goto('/login');
		await expect(page).toHaveURL(/\/login/);
	});
});
