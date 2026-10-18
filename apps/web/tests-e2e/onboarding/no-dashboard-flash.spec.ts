import type { BrowserContext, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * A fresh account must reach /onboarding without the app shell (and so the
 * dashboard inside it) ever being attached to the DOM first (decisions
 * § 2122). The shell used to paint, then the layout's gate bounced to
 * /onboarding once the profile hydrated. A MutationObserver installed before
 * any page script records the first time `.app-shell` is attached; the
 * assertion is that it never was by the time the wizard heading shows.
 */

const WIZARD_HEADING = /What should we call you/i;

async function watchForShell(page: Page): Promise<void> {
	await page.addInitScript(() => {
		const w = window as unknown as { __shellAttachedAt?: string };
		const check = () => {
			if (w.__shellAttachedAt == null && document.querySelector('.app-shell')) {
				w.__shellAttachedAt = location.pathname;
			}
		};
		new MutationObserver(check).observe(document, { childList: true, subtree: true });
		check();
	});
}

async function shellAttachedAt(page: Page): Promise<string | null> {
	return page.evaluate(
		() => (window as unknown as { __shellAttachedAt?: string }).__shellAttachedAt ?? null,
	);
}

test.describe('a not-yet-onboarded account never sees the dashboard first', () => {
	let user: SagaUser;
	let ctx: BrowserContext | null = null;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1);
		const { error } = await getAdminClient()
			.from('user_profiles')
			.update({ onboarded_at: null })
			.eq('id', user.id);
		if (error) throw error;
	});

	test.afterEach(async () => {
		await ctx?.close();
		ctx = null;
	});

	test.afterAll(async () => {
		if (user) await deleteSagaUsers([user]);
	});

	test('email sign-in goes straight to /onboarding', async ({ browser }) => {
		ctx = await browser.newContext({ storageState: { cookies: [], origins: [] } });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		await watchForShell(page);
		const visited: string[] = [];
		page.on('framenavigated', (frame) => {
			if (frame === page.mainFrame()) visited.push(new URL(frame.url()).pathname);
		});

		await page.goto('/login');
		await page.waitForLoadState('networkidle');
		await page.locator('input[type="email"]').fill(user.email);
		await page.locator('input[type="password"]').fill(user.password);
		await page.locator('form button[type="submit"]').click();

		await page.waitForURL(/\/onboarding$/, { timeout: 15_000 });
		await expect(page.getByRole('heading', { name: WIZARD_HEADING })).toBeVisible({
			timeout: 10_000,
		});
		expect(await shellAttachedAt(page)).toBeNull();
		expect(visited).not.toContain('/dashboard');
	});

	test('reloading /dashboard holds the shell and lands on /onboarding', async ({ browser }) => {
		ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		await watchForShell(page);

		await page.goto('/dashboard');
		await page.waitForURL(/\/onboarding$/, { timeout: 15_000 });
		await expect(page.getByRole('heading', { name: WIZARD_HEADING })).toBeVisible({
			timeout: 10_000,
		});
		expect(await shellAttachedAt(page)).toBeNull();

		// A reload of /onboarding itself must not route through the shell.
		await page.reload();
		await expect(page.getByRole('heading', { name: WIZARD_HEADING })).toBeVisible({
			timeout: 10_000,
		});
		expect(await shellAttachedAt(page)).toBeNull();
	});
});
