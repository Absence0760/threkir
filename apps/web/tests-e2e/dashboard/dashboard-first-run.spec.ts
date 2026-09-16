import { expect, test } from '@playwright/test';

import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * The dashboard's brand-new-account state (#905).
 *
 * `/dashboard` derives thirteen cards from runs and gym sessions. An account
 * that has neither used to render every one of them empty or zeroed, with the
 * only "add a run" call to action ~700 lines down the page underneath the
 * training-load model — the first screen after onboarding, and the one screen
 * where a new runner has no idea what to do next.
 *
 * This pins both halves of the branch, because the risk runs both ways: a
 * regression that never shows the first-run card leaves the empty grid, and a
 * regression that never *stops* showing it hides the whole dashboard from
 * every real account.
 *
 * Saga users are created with no runs and no gym sessions, so the empty half
 * needs no seeding — which is exactly the state under test.
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

test.describe('dashboard first-run state', () => {
	let user: SagaUser;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['First Run Runner'] });
	});

	test.afterAll(async () => {
		if (user) await deleteSagaUsers([user]);
	});

	test('an account with no runs gets one action, not thirteen empty cards — and loses it once a run lands', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();

		try {
			// ── Empty account ────────────────────────────────────────────
			await page.goto('/dashboard');

			const firstRun = page.getByTestId('dash-first-run');
			await expect(firstRun).toBeVisible({ timeout: 15_000 });

			// The derived-metric block is gone in its entirety. These three
			// are the load-bearing ones: the stat grid is the page's former
			// opening, the source filter gates everything under it, and the
			// training-load chart is the most advanced thing on the page.
			await expect(page.locator('.stat-grid')).toHaveCount(0);
			await expect(page.locator('.filter-row')).toHaveCount(0);
			await expect(page.locator('.fitness-card')).toHaveCount(0);

			// Both actions are real and reachable — a dead-end empty state is
			// the failure mode this card exists to remove.
			await expect(page.getByTestId('dash-first-run-log')).toHaveAttribute(
				'href',
				'/runs/new'
			);
			await expect(page.getByTestId('dash-first-run-import')).toHaveAttribute(
				'href',
				'/settings/integrations'
			);

			// The primary action actually goes somewhere that can create a run.
			await page.getByTestId('dash-first-run-log').click();
			await expect(page).toHaveURL(/\/runs\/new$/);

			// ── One run later ────────────────────────────────────────────
			await insertRun({
				user_id: user.id,
				started_at: new Date(Date.now() - 86_400_000).toISOString(),
				distance_m: 5_000,
				duration_s: 1_500,
			});

			await page.goto('/dashboard');
			await expect(page.locator('.stat-grid')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('dash-first-run')).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
