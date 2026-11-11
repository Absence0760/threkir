import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Grisnir waits in the onboarding side panel only once the runner's
 * `show_mascot` is known: a settings read that succeeds with no value is a
 * new account and shows him, and one that fails with nothing cached keeps him
 * hidden, as EmptyState and the flyover do (#1364).
 *
 * Runs as a throwaway runner so deleting the settings row reaches no other
 * spec's user. Walks no step, so nothing is saved.
 */

let runner: SagaUser;

test.beforeAll(async () => {
	[runner] = await createSagaUsers(1, { displayNames: ['Onboarding Grisnir Runner'] });
});

test.afterAll(async () => {
	await deleteSagaUsers([runner].filter(Boolean));
});

test.beforeEach(async () => {
	const { error } = await getAdminClient().from('user_settings').delete().eq('user_id', runner.id);
	if (error) throw new Error(`user_settings reset failed: ${error.message}`);
});

const isUserSettings = (url: URL) => url.pathname.endsWith('/rest/v1/user_settings');

test('a new account with no settings row sees him in the side panel', async ({ browser }) => {
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await context.newPage();
	try {
		await page.setViewportSize({ width: 1440, height: 900 });
		await page.goto('/onboarding');
		await expect(page.getByRole('heading', { name: /What should we call you/i })).toBeVisible();
		await expect(page.getByTestId('onboarding-grisnir')).toBeVisible({ timeout: 15_000 });
	} finally {
		await context.close();
	}
});

test('a settings read that fails with nothing cached keeps him hidden', async ({ browser, mockRoute }) => {
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	const page = await context.newPage();
	try {
		await mockRoute(page, isUserSettings, (route) =>
			route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"down"}' }),
		);
		// The signed-in storage state carries a warm settings cache, which is
		// a known answer; empty it so the failed read is all there is.
		await page.addInitScript(() => {
			for (const k of Object.keys(localStorage)) {
				if (k.startsWith('settings_cache_')) localStorage.removeItem(k);
			}
		});
		await page.setViewportSize({ width: 1440, height: 900 });
		const settingsFailed = page.waitForResponse((r) => isUserSettings(new URL(r.url())) && r.status() === 500);
		await page.goto('/onboarding');
		await expect(page.getByRole('heading', { name: /What should we call you/i })).toBeVisible();
		await expect(page.locator('.rail li').first()).toBeVisible();
		await settingsFailed;
		// The read's answer lands after the response; let it settle before
		// judging that he stayed away.
		await page.waitForLoadState('networkidle');
		await expect(page.getByTestId('onboarding-grisnir')).toHaveCount(0);
	} finally {
		await context.close();
	}
});
