import { expect, test } from '../fixtures/test';

import type { BrowserContext } from '@playwright/test';

import { acceptCookieConsent } from '../fixtures/helpers';
import {
	createThrowawayPlan,
	deleteThrowawayPlan,
	THROWAWAY_PLAN_DONE,
	type ThrowawayPlan
} from '../fixtures/throwaway-plan';

/**
 * Plans journey — mark 2 workouts done in a row, then revert 1, and
 * watch BOTH the day-grid `.day[data-status="done"]` count and the hero
 * progress ring `.pct` value stay in sync at every step.
 *
 * Same shape as cross-cutting/dashboard-journey.spec.ts: snapshot →
 * mutate → verify → mutate → verify → revert. Pins the
 * `markWorkoutCompleted` → `load()` → re-render pipeline against the
 * cumulative case (one mark, then another, then unmark) — the
 * batch-14 day-cell test only covered a single mark.
 *
 * Each run gets a plan and an account of its own (fixtures/throwaway-plan.ts),
 * so the spec re-runs on a used database and no other spec's completions on
 * the seeded plan reach its counts.
 */

test.describe('plans journey', () => {
	test.describe.configure({ timeout: 90_000 });

	let plan: ThrowawayPlan | undefined;
	let ctx: BrowserContext | undefined;
	test.beforeEach(async () => {
		plan = await createThrowawayPlan('e2e plans journey');
	});
	test.afterEach(async () => {
		await ctx?.close();
		ctx = undefined;
		await deleteThrowawayPlan(plan);
		plan = undefined;
	});

	test('mark 2 workouts done in sequence, revert 1 — pct + day-grid stay in lockstep', async ({
		browser
	}) => {
		ctx = await browser.newContext({ storageState: plan!.user.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		await page.goto(`/plans/${plan!.planId}`);
		await expect(page.getByRole('heading', { level: 1, name: plan!.name }))
			.toBeVisible({ timeout: 10_000 });

		const pct = page.locator('.pct');
		const completedCount = page.locator('.day-grid .day[data-status="done"]');

		const readPct = async (): Promise<number> => {
			const txt = (await pct.textContent()) ?? '';
			const m = txt.match(/(\d+)/);
			return m ? parseInt(m[1], 10) : -1;
		};

		// ── Snapshot ───────────────────────────────────────────────
		// The plan's first two long runs are done through a linked run.
		await expect(completedCount).toHaveCount(THROWAWAY_PLAN_DONE, { timeout: 10_000 });
		const initialCompleted = THROWAWAY_PLAN_DONE;
		const initialPct = await readPct();
		expect(initialPct).toBeGreaterThanOrEqual(0);

		// ── Mark workout 1 done ────────────────────────────────────
		await test.step('mark first non-rest, non-completed workout done', async () => {
			await page
				.locator('.day-grid .day:not(.rest):not([data-status="done"]) .day-link')
				.first()
				.click();
			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });
			await modal.getByRole('button', { name: 'Mark as done' }).click();
			await expect(modal).toHaveCount(0);
		});

		await expect(completedCount).toHaveCount(initialCompleted + 1, { timeout: 10_000 });
		await expect.poll(readPct, { timeout: 10_000 }).toBeGreaterThan(initialPct);
		const afterFirstPct = await readPct();

		// ── Mark workout 2 done ────────────────────────────────────
		await test.step('mark a second non-rest, non-completed workout done', async () => {
			await page
				.locator('.day-grid .day:not(.rest):not([data-status="done"]) .day-link')
				.first()
				.click();
			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });
			await modal.getByRole('button', { name: 'Mark as done' }).click();
			await expect(modal).toHaveCount(0);
		});

		await expect(completedCount).toHaveCount(initialCompleted + 2, { timeout: 10_000 });
		await expect.poll(readPct, { timeout: 10_000 }).toBeGreaterThan(afterFirstPct);
		const afterSecondPct = await readPct();

		// ── Revert one via UI ──────────────────────────────────────
		// Tricky bit: the planted completions are via `completed_run_id`
		// (a real run linked); its modal disables "Mark not done"
		// with the title "A run is linked — unlink it from the
		// workout detail page first." So the planted completed cells
		// can NOT be reverted from the editor. The two cells the
		// test marked use `manually_completed=true` and CAN.
		//
		// Pick the completed cell whose editor exposes an enabled
		// "Mark not done" button. Walking from .last() backward (the
		// test marks are later than the planted completions in week
		// order, but day-of-week within a week varies — safest to
		// just iterate).
		await test.step('revert one of the test-marked workouts via the editor', async () => {
			const completedDays = page.locator('.day-grid .day[data-status="done"]:not(.rest) .day-link');
			const total = await completedDays.count();
			let reverted = false;
			for (let i = total - 1; i >= 0; i--) {
				await completedDays.nth(i).click();
				const modal = page.locator('.modal');
				await expect(modal).toBeVisible({ timeout: 5_000 });
				const btn = modal.getByRole('button', { name: 'Mark not done' });
				if (await btn.isEnabled()) {
					await btn.click();
					await expect(modal).toHaveCount(0);
					reverted = true;
					break;
				}
				// Linked-run cell — close modal and try the next.
				await page.locator('.modal-close').click();
				await expect(modal).toHaveCount(0);
			}
			expect(reverted, 'no manually-completed cell found to revert')
				.toBe(true);
		});

		await expect(completedCount).toHaveCount(initialCompleted + 1, { timeout: 10_000 });
		// pct dropped from afterSecondPct back toward afterFirstPct,
		// but stays >= initialPct (one of the two test-marks remains).
		await expect
			.poll(readPct, { timeout: 10_000 })
			.toBeLessThan(afterSecondPct);
		expect(await readPct()).toBeGreaterThanOrEqual(initialPct);
	});
});
