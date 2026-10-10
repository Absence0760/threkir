import { expect, test, type Locator, type Page } from '@playwright/test';

import { signIn, signOut, switchRunsToAllTime } from '../fixtures/helpers';
import { USER_A } from '../fixtures/users';

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

/**
 * A whole signed-in session, navigated only by clicking.
 *
 * Every surface below has a spec of its own, and nearly all of them
 * arrive by page.goto on the URL they test. That leaves the seams
 * between surfaces unwalked: the sidebar link, the run-surface tabs, a
 * list card into its detail, and each detail's back link out again —
 * which for /runs, /plans and /history is history.back() into a
 * snapshot restore rather than a fresh load. This spec signs in through
 * the form and then never types a URL: dashboard → Runs → a run → All
 * runs → Routes → a route → back → Plans → the seed plan → All plans →
 * History → a run row → back → sign out.
 *
 * Read-only: it creates nothing. It starts from an empty storage state
 * so the sign-out revokes only the session this test minted (see
 * cross-cutting/sign-in-out.spec.ts).
 */

async function openFromList(page: Page, card: Locator, detailUrl: RegExp): Promise<string> {
	const href = await card.getAttribute('href');
	expect(href, 'a list card must link to its detail').toBeTruthy();
	await card.click();
	await page.waitForURL(detailUrl, { timeout: 10_000 });
	expect(new URL(page.url()).pathname).toBe(href);
	return href!;
}

test.describe('click-through session journey', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('sign in → runs → routes → plans → history → sign out, by clicks alone', async ({
		page
	}) => {
		const sidebar = page.locator('nav.sidebar');
		const surfaceTabs = page.getByRole('navigation', { name: /Run surface sections/ });

		await test.step('sign in through the form and land on the dashboard', async () => {
			await signIn(page, USER_A);
			await expect(page).toHaveURL(/\/dashboard$/, { timeout: 10_000 });
			await expect(
				page.getByRole('heading', { level: 2, name: 'Distance', exact: true })
			).toBeVisible({ timeout: 10_000 });
		});

		await test.step('Runs in the sidebar → open a run → All runs', async () => {
			await sidebar.getByRole('link', { name: 'Runs', exact: true }).click();
			await page.waitForURL(/\/runs$/, { timeout: 10_000 });
			await switchRunsToAllTime(page);
			const first = page.locator('.run-card').first();
			await expect(first).toBeVisible({ timeout: 10_000 });
			const before = await page.locator('.run-card').count();

			await openFromList(page, first, /\/runs\/[0-9a-f-]+$/);
			await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.key-stat-value').first()).toBeVisible({ timeout: 10_000 });

			await page.getByRole('link', { name: /All runs/ }).first().click();
			await page.waitForURL(/\/runs$/, { timeout: 10_000 });
			await expect(page.getByLabel('Date range')).toHaveValue('all');
			await expect(page.locator('.run-card')).toHaveCount(before, { timeout: 10_000 });
		});

		await test.step('Routes tab → open a route → back to My routes', async () => {
			await surfaceTabs.getByRole('link', { name: /^Routes$/ }).click();
			await page.waitForURL(/\/routes(\?.*)?$/, { timeout: 10_000 });
			const first = page.locator('.route-card').first();
			await expect(first).toBeVisible({ timeout: 10_000 });

			await openFromList(page, first, /\/routes\/[0-9a-f-]+$/);
			await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

			await page.locator('a.panel-back').click();
			await page.waitForURL(/\/routes(\?.*)?$/, { timeout: 10_000 });
			await expect(page.locator('.route-card').first()).toBeVisible({ timeout: 10_000 });
		});

		await test.step('Plans tab → open the seed plan → All plans', async () => {
			await surfaceTabs.getByRole('link', { name: /^Plans$/ }).click();
			await page.waitForURL(/\/plans$/, { timeout: 10_000 });
			const card = page.locator(`a.card[href="/plans/${SEED_PLAN_ID}"]`);
			await expect(card).toBeVisible({ timeout: 10_000 });

			// Click the card's title, not its centre: the card also hosts the
			// Abandon / Delete buttons, which preventDefault the navigation.
			await card.getByRole('heading', { level: 3 }).click();
			await page.waitForURL(new RegExp(`/plans/${SEED_PLAN_ID}$`), { timeout: 10_000 });
			await expect(
				page.getByRole('heading', { level: 1, name: /Richmond Half 2026/ })
			).toBeVisible({ timeout: 10_000 });

			await page.getByRole('link', { name: /All plans/ }).first().click();
			await page.waitForURL(/\/plans$/, { timeout: 10_000 });
			await expect(card).toBeVisible({ timeout: 10_000 });
		});

		await test.step('History in the sidebar → open a run row → back to the timeline', async () => {
			await sidebar.getByRole('link', { name: 'History', exact: true }).click();
			await page.waitForURL(/\/history(\?.*)?$/, { timeout: 10_000 });
			const runRow = page.locator('a.timeline-row[data-kind="run"]').first();
			await expect(runRow).toBeVisible({ timeout: 10_000 });

			await openFromList(page, runRow, /\/runs\/[0-9a-f-]+$/);
			await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });

			await page.getByRole('link', { name: /All runs/ }).first().click();
			await page.waitForURL(/\/history(\?.*)?$/, { timeout: 10_000 });
			await expect(page.locator('a.timeline-row[data-kind="run"]').first()).toBeVisible({
				timeout: 10_000
			});
		});

		await test.step('sign out from the profile popover', async () => {
			await signOut(page);
			await expect(sidebar).toHaveCount(0);
		});
	});
});
