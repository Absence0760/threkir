import { expect, test } from '@playwright/test';

import { expandTrainingLoad } from '../fixtures/dashboard';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * A near-zero training load must not take the dashboard down.
 *
 * One 10-second run gives a load of a fraction of a point, so the training-load
 * chart's padded axis spans about -1..1 and the tick ladder picked a 0.5 step.
 * The labels are rounded to whole numbers and are also the keyed-each key, so
 * -0.5 and 0 both keyed as 0, Svelte threw `each_key_duplicate`, and the whole
 * page rendered "500 Internal Error". A new account's first short test run hit
 * it in prod.
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
	);
}

test.describe('dashboard with a near-zero training load', () => {
	let user: SagaUser;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Tiny Load Runner'] });
		await insertRun({
			user_id: user.id,
			started_at: new Date(Date.now() - 20 * 60_000).toISOString(),
			distance_m: 3,
			duration_s: 10,
			source: 'app',
		});
	});

	test.afterAll(async () => {
		if (user) await deleteSagaUsers([user]);
	});

	test('renders the training-load chart with distinct whole-number ticks', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		const errors: string[] = [];
		page.on('pageerror', (e) => errors.push(e.message));
		page.on('console', (m) => {
			if (m.type() === 'error' && m.text().includes('each_key_duplicate')) errors.push(m.text());
		});

		try {
			await page.goto('/dashboard');
			await expandTrainingLoad(page);

			const ticks = page.locator('.fitness-card .y-tick');
			await expect(ticks.first()).toBeVisible({ timeout: 15_000 });
			await expect(page.getByText('Internal Error')).toHaveCount(0);

			const labels = await ticks.allTextContents();
			expect(labels.length).toBeGreaterThan(1);
			expect(new Set(labels).size).toBe(labels.length);
			for (const l of labels) expect(l.trim()).toMatch(/^-?\d+$/);
			expect(errors).toEqual([]);
		} finally {
			await ctx.close();
		}
	});
});

test.describe('dashboard whose only run is 0 m', () => {
	let user: SagaUser;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Zero Distance Runner'] });
		await insertRun({
			user_id: user.id,
			started_at: new Date(Date.now() - 20 * 60_000).toISOString(),
			distance_m: 0,
			duration_s: 10,
			source: 'app',
		});
	});

	test.afterAll(async () => {
		if (user) await deleteSagaUsers([user]);
	});

	// With every bar at 0 m the tallest bar was 0 too, so each height was
	// 0 / 0 and rendered as `height: NaN%`.
	test('mileage bars carry a finite height', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();

		try {
			await page.goto('/dashboard');
			const bars = page.locator('.bar-col .bar');
			await expect(bars.first()).toBeAttached({ timeout: 15_000 });
			await expect(page.getByText('Internal Error')).toHaveCount(0);

			const styles = await bars.evaluateAll((els) => els.map((e) => e.getAttribute('style') ?? ''));
			expect(styles.length).toBeGreaterThan(0);
			for (const s of styles) expect(s).not.toContain('NaN');
		} finally {
			await ctx.close();
		}
	});
});
