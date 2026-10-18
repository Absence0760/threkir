import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { browserDate, noonOnBrowserDay } from '../fixtures/dates';
import { readRow } from '../fixtures/db-read';
import { acceptCookieConsent, setStorageOnLoad } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * First-time plan discovery on /dashboard (training.md § First-time plan
 * discovery). A runner with no plan and a measured 5K from the last eight
 * weeks is offered a plan seeded from it; the wizard fills its recent-5K field
 * and leaves the "reflects my fitness today" box unticked, so the time sets no
 * paces until they confirm it. "Not now" is stored in the universal settings
 * bag, and only a run started after it brings the suggestion back.
 *
 * The pure pick (window, fastest, DNF and activity filters) is unit-tested in
 * recent_5k_suggestion.test.ts; this pins the surface.
 */

const KEY = 'plan_suggestion_dismissed_at';

let runner: SagaUser;
let extraRunIds: string[] = [];

test.beforeAll(async () => {
	[runner] = await createSagaUsers(1, { displayNames: ['Recent 5K Runner'] });
	// The one that counts: a 24:10 5K inside a run ten days ago.
	await insertRun({ user_id: runner.id, started_at: noonOnBrowserDay(-10), distance_m: 8_000, duration_s: 2_900, fastest_5k_s: 1450 });
	// Faster, but each is ruled out: too old, a walk, a DNF.
	await insertRun({ user_id: runner.id, started_at: noonOnBrowserDay(-70), distance_m: 5_000, duration_s: 1_300, fastest_5k_s: 1300 });
	await insertRun({ user_id: runner.id, started_at: noonOnBrowserDay(-5), distance_m: 6_000, duration_s: 3_600, fastest_5k_s: 1200, activity_type: 'walk' });
	await insertRun({ user_id: runner.id, started_at: noonOnBrowserDay(-3), distance_m: 6_000, duration_s: 1_600, fastest_5k_s: 1250, is_dnf: true });
});

test.afterAll(async () => {
	await deleteSagaUsers([runner].filter(Boolean));
});

test.afterEach(async () => {
	const admin = getAdminClient();
	if (extraRunIds.length > 0) {
		const { error } = await admin.from('runs').delete().in('id', extraRunIds);
		if (error) throw error;
		extraRunIds = [];
	}
	const { error: planErr } = await admin.from('training_plans').delete().eq('user_id', runner.id);
	if (planErr) throw planErr;
	const row = await readRow(
		'runner settings',
		admin.from('user_settings').select('prefs').eq('user_id', runner.id).single(),
	);
	const prefs = { ...((row.prefs as Record<string, unknown> | null) ?? {}) };
	if (KEY in prefs) {
		delete prefs[KEY];
		const { error } = await admin.from('user_settings').update({ prefs }).eq('user_id', runner.id);
		if (error) throw error;
	}
});

async function openDashboard(browser: Browser, setup?: (page: Page) => Promise<void>): Promise<Page> {
	const context = await browser.newContext({ storageState: runner.storageStatePath });
	await acceptCookieConsent(context);
	const page = await context.newPage();
	if (setup) await setup(page);
	await page.goto('/dashboard');
	return page;
}

async function dismissedStamp(): Promise<unknown> {
	const row = await readRow(
		'runner settings',
		getAdminClient().from('user_settings').select('prefs').eq('user_id', runner.id).single(),
	);
	return (row.prefs as Record<string, unknown> | null)?.[KEY];
}

test.describe('dashboard recent-5K plan suggestion', () => {
	test('offers the fastest measured 5K of the last eight weeks in place of the plain plan entry', async ({ browser }) => {
		const page = await openDashboard(browser);
		try {
			const card = page.getByTestId('dash-recent-5k');
			await expect(card).toBeVisible({ timeout: 15_000 });
			const day = String(new Date(noonOnBrowserDay(-10)).getUTCDate());
			await expect(card.locator('h3')).toContainText('24:10');
			await expect(card.locator('h3')).toContainText(day);
			await expect(page.getByTestId('dash-recent-5k-build')).toHaveAttribute(
				'href',
				'/plans/new?type=training&recent5k=1450',
			);
			await expect(page.locator('.plan-promo')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});

	test('building from it fills the wizard but leaves the time unconfirmed', async ({ browser }) => {
		const page = await openDashboard(browser);
		try {
			await page.getByTestId('dash-recent-5k-build').click({ timeout: 15_000 });
			await expect(page).toHaveURL(/\/plans\/new\?type=training&recent5k=1450$/);
			const fieldset = page.locator('fieldset', { hasText: 'Recent 5K time' });
			await expect(fieldset).toBeVisible({ timeout: 15_000 });
			const [minutes, seconds] = await fieldset.locator('input[type="number"]').all();
			await expect(minutes).toHaveValue('24');
			await expect(seconds).toHaveValue('10');
			const confirm = page.getByRole('checkbox', { name: /current fitness/i });
			await expect(confirm).not.toBeChecked();
			const note = page.getByTestId('plan-recent-5k-suggested');
			await expect(note).toBeVisible();
			await expect(page.getByText('too fast for a returning runner')).toBeVisible();
			await confirm.check();
			await expect(note).toBeHidden();
			await expect(page.getByText('too fast for a returning runner')).toBeHidden();
		} finally {
			await page.context().close();
		}
	});

	test('a wizard link carrying a time it cannot take fills nothing', async ({ browser }) => {
		const page = await openDashboard(browser);
		try {
			await page.goto('/plans/new?type=training&recent5k=600');
			const fieldset = page.locator('fieldset', { hasText: 'Recent 5K time' });
			await expect(fieldset).toBeVisible({ timeout: 15_000 });
			const [minutes, seconds] = await fieldset.locator('input[type="number"]').all();
			await expect(minutes).toHaveValue('');
			await expect(seconds).toHaveValue('');
			await expect(page.getByTestId('plan-recent-5k-suggested')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});

	test('"Not now" is stored server-side and only a newer 5K brings it back', async ({ browser }) => {
		const page = await openDashboard(browser);
		try {
			await page.getByTestId('dash-recent-5k-dismiss').click({ timeout: 15_000 });
			await expect(page.getByTestId('dash-recent-5k')).toHaveCount(0);
			await expect(page.locator('.plan-promo')).toBeVisible();
			await expect.poll(dismissedStamp).toEqual(expect.any(String));
			const stamp = (await dismissedStamp()) as string;
			expect(Math.abs(Date.parse(stamp) - Date.now())).toBeLessThan(5 * 60_000);

			await page.reload();
			await expect(page.locator('.plan-promo')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('dash-recent-5k')).toHaveCount(0);

			// Two days on, a 25:00 5K run since the dismissal is offered, though
			// it is slower than the one waved away. The stamp is moved back
			// rather than the run forward: a run in the future is never offered.
			const admin = getAdminClient();
			const row = await readRow(
				'runner settings',
				admin.from('user_settings').select('prefs').eq('user_id', runner.id).single(),
			);
			const prefs = { ...((row.prefs as Record<string, unknown> | null) ?? {}), [KEY]: noonOnBrowserDay(-2) };
			const { error } = await admin.from('user_settings').update({ prefs }).eq('user_id', runner.id);
			if (error) throw error;
			await page.evaluate((id) => localStorage.removeItem(`settings_cache_universal_${id}`), runner.id);
			await page.reload();
			await expect(page.locator('.plan-promo')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('dash-recent-5k')).toHaveCount(0);
			extraRunIds.push(
				await insertRun({
					user_id: runner.id,
					started_at: noonOnBrowserDay(-1),
					distance_m: 6_000,
					duration_s: 1_850,
					fastest_5k_s: 1500,
				}),
			);
			await page.reload();
			await expect(page.getByTestId('dash-recent-5k').locator('h3')).toContainText('25:00', { timeout: 15_000 });
			await expect(page.getByTestId('dash-recent-5k-build')).toHaveAttribute(
				'href',
				'/plans/new?type=training&recent5k=1500',
			);
		} finally {
			await page.context().close();
		}
	});

	test('a refused dismissal says it may come back', async ({ browser }) => {
		const page = await openDashboard(browser);
		try {
			await expect(page.getByTestId('dash-recent-5k')).toBeVisible({ timeout: 15_000 });
			await page.route('**/rest/v1/user_settings*', (route) =>
				route.request().method() === 'GET'
					? route.continue()
					: route.fulfill({
							status: 403,
							contentType: 'application/json',
							body: JSON.stringify({ code: '42501', message: 'permission denied for table user_settings' }),
						}),
			);
			await page.getByTestId('dash-recent-5k-dismiss').click();
			await expect(page.locator('.toast.toast-error')).toContainText("Couldn't save that, so the suggestion may come back.");
			await expect(page.getByTestId('dash-recent-5k')).toHaveCount(0);
			expect(await dismissedStamp()).toBeUndefined();
		} finally {
			await page.context().close();
		}
	});

	test('with the settings bag unreadable it shows the plain plan entry, not the suggestion', async ({ browser }) => {
		// The bag is unknown only with no cached copy either: a cached bag is the
		// dashboard's offline answer and carries any dismissal made here.
		const page = await openDashboard(browser, async (p) => {
			await setStorageOnLoad(p, { local: { [`settings_cache_universal_${runner.id}`]: null } });
			await p.route('**/rest/v1/user_settings*', (route) => route.abort());
		});
		try {
			await expect(page.locator('.plan-promo')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('dash-recent-5k')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});

	test('a runner with a plan, even one not started yet, is not offered it', async ({ browser }) => {
		const { error } = await getAdminClient().from('training_plans').insert({
			user_id: runner.id,
			name: 'e2e recent-5k queued',
			goal_event: 'distance_10k',
			goal_distance_m: 10_000,
			start_date: browserDate(10),
			end_date: browserDate(50),
			days_per_week: 4,
			status: 'active',
		});
		if (error) throw error;
		const page = await openDashboard(browser);
		try {
			await expect(page.locator('.plan-hero .plan-hero-relation')).toHaveText('Starts in 10 days', { timeout: 15_000 });
			await expect(page.getByTestId('dash-recent-5k')).toHaveCount(0);
			await expect(page.locator('.plan-promo')).toHaveCount(0);
		} finally {
			await page.context().close();
		}
	});
});
