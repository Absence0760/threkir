import { expect, test, type Browser, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { readRow } from '../fixtures/db-read';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * The show_gym / show_nutrition switches on web (decisions § 1739 amendment).
 *
 * A fresh saga user has logged no lift and no meal and made no choice, so both
 * modalities resolve hidden: no sidebar item, no Log entry. Hiding removes the
 * entry points, not the pages, so /gym still loads by URL. The two writers are
 * covered: the Settings → Units & display switch, and the first-run "Log a gym
 * session" link, which switches Gym on before it lands on /gym.
 *
 * Absence is only meaningful once the one-row presence reads have answered —
 * before them the sidebar hides both items anyway — so each absence check
 * waits for those responses first.
 */
test.describe.configure({ mode: 'serial' });

test.describe('gym and nutrition visibility switches', () => {
	let user: SagaUser;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Modality Saga'] });
	});

	test.afterAll(async () => {
		if (user) await deleteSagaUsers([user]).catch(() => {});
	});

	async function clearChoices(): Promise<void> {
		const { error } = await getAdminClient()
			.from('user_settings')
			.upsert({ user_id: user.id, prefs: {} }, { onConflict: 'user_id' });
		expect(error).toBeNull();
	}

	async function storedChoice(key: 'show_gym' | 'show_nutrition'): Promise<unknown> {
		const row = await readRow(
			'user_settings by user_id',
			getAdminClient().from('user_settings').select('prefs').eq('user_id', user.id).single(),
		);
		return (row.prefs as Record<string, unknown> | null)?.[key];
	}

	async function openPage(browser: Browser): Promise<Page> {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		// The consent banner is a role="dialog" that can sit over the nav.
		await ctx.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});
		return ctx.newPage();
	}

	// The presence read is `select=id … limit=1`; /dashboard reads both tables
	// for its own cards too, so the URL is matched that narrowly.
	function presenceReads(page: Page) {
		const presence = (table: string) => (r: { url(): string }) => {
			const url = r.url();
			return url.includes(`/rest/v1/${table}?`) && url.includes('select=id&') && url.includes('limit=1');
		};
		return Promise.all([
			page.waitForResponse(presence('gym_workouts')),
			page.waitForResponse(presence('food_log')),
		]);
	}

	function navLabel(page: Page, label: string) {
		return page.locator('nav.sidebar .nav-label', { hasText: new RegExp(`^${label}$`) });
	}

	test('a fresh account sees neither Gym nor Nutrition, and History offers only Log run', async ({
		browser,
	}) => {
		await clearChoices();
		const page = await openPage(browser);
		try {
			const reads = presenceReads(page);
			await page.goto('/dashboard');
			await reads;
			await expect(navLabel(page, 'Dashboard')).toBeVisible({ timeout: 15_000 });
			await expect(navLabel(page, 'Runs')).toBeVisible();
			await expect(navLabel(page, 'Gym')).toHaveCount(0);
			await expect(navLabel(page, 'Nutrition')).toHaveCount(0);

			await page.goto('/history');
			await expect(page.getByRole('button', { name: 'Log run', exact: true })).toBeVisible({
				timeout: 15_000,
			});
			await expect(page.getByRole('button', { name: 'Log', exact: true })).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});

	test('a hidden Gym still loads by URL', async ({ browser }) => {
		await clearChoices();
		const page = await openPage(browser);
		try {
			await page.goto('/gym');
			await expect(page.getByRole('heading', { level: 1, name: 'Gym' })).toBeVisible({
				timeout: 15_000,
			});
			await expect(navLabel(page, 'Gym')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});

	test('switching Show Gym on in settings brings the sidebar item back', async ({ browser }) => {
		await clearChoices();
		const page = await openPage(browser);
		try {
			const reads = presenceReads(page);
			await page.goto('/settings/display');
			await reads;
			const showGym = page.getByRole('checkbox', { name: /^Show Gym/ });
			const showNutrition = page.getByRole('checkbox', { name: /^Show Nutrition/ });
			await expect(showGym).not.toBeChecked({ timeout: 15_000 });
			await expect(showNutrition).not.toBeChecked();
			await expect(navLabel(page, 'Gym')).toHaveCount(0);

			await showGym.check();
			await expect(navLabel(page, 'Gym')).toBeVisible();
			await expect(navLabel(page, 'Nutrition')).toHaveCount(0);
			await expect.poll(() => storedChoice('show_gym'), { timeout: 10_000 }).toBe(true);
			expect(await storedChoice('show_nutrition')).toBeUndefined();
		} finally {
			await page.context().close();
		}
	});

	test('the first-run gym link switches Gym on before it lands on /gym', async ({ browser }) => {
		await clearChoices();
		const page = await openPage(browser);
		try {
			const reads = presenceReads(page);
			await page.goto('/dashboard');
			await reads;
			await expect(navLabel(page, 'Gym')).toHaveCount(0);
			const link = page.getByTestId('dash-first-run-gym');
			await expect(link).toBeVisible({ timeout: 15_000 });

			await link.click();
			await expect(page).toHaveURL(/\/gym$/);
			await expect(navLabel(page, 'Gym')).toBeVisible();
			await expect.poll(() => storedChoice('show_gym'), { timeout: 10_000 }).toBe(true);
		} finally {
			await page.context().close();
		}
	});

	test('a runner who switched Gym off is not offered the first-run gym link', async ({
		browser,
	}) => {
		const { error } = await getAdminClient()
			.from('user_settings')
			.upsert({ user_id: user.id, prefs: { show_gym: false } }, { onConflict: 'user_id' });
		expect(error).toBeNull();
		const page = await openPage(browser);
		try {
			await page.goto('/dashboard');
			await expect(page.getByTestId('dash-first-run')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('dash-first-run-gym')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});
});
