import { expect, test, type Page } from '@playwright/test';

import { expandTrainingLoad } from '../fixtures/dashboard';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * A derived metric's definition is reachable without a mouse (#902 §1).
 *
 * The dashboard's VO₂ max / CTL / ATL / TSB tiles carried plain-English
 * definitions in all seven locales, in `title=` attributes — which a touch
 * screen never shows and a keyboard never reaches, so on a phone the copy may
 * as well not have existed. `<MetricLabel>` puts each one behind a real
 * button. This pins the three ways in that a hover-only tooltip did not have:
 * a keyboard, a tap, and a screen reader's view of the same markup.
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

const CTL_DEFINITION = /Fitness \(CTL\) — your rolling 42-day training load/;

/// The snapshot card, not the training-load chart that shares its class.
async function openDashboard(page: Page) {
	await page.goto('/dashboard');
	// This runner has three runs, so the page renders at `simple` and the
	// snapshot is behind the named fold (§ 1656) — the definitions are what
	// this spec is about, not their depth.
	await expandTrainingLoad(page);
	const card = page.locator('.fitness-card').filter({ has: page.getByTestId('metric-info-vo2max') });
	await expect(card).toBeVisible({ timeout: 15_000 });
	return card;
}

test.describe('dashboard metric definitions', () => {
	let runner: SagaUser;

	test.beforeAll(async () => {
		[runner] = await createSagaUsers(1, { displayNames: ['Metric Label Runner'] });
		for (const [daysAgo, distance_m, duration_s] of [
			[2, 10_000, 2_700],
			[4, 6_000, 1_650],
			[6, 12_000, 3_400],
		] as const) {
			await insertRun({
				user_id: runner.id,
				started_at: new Date(Date.now() - daysAgo * 86_400_000).toISOString(),
				distance_m,
				duration_s,
				source: 'app',
			});
		}
	});

	test.afterAll(async () => {
		if (runner) await deleteSagaUsers([runner]);
	});

	test('the keyboard opens a definition, Escape closes it and returns focus, and no tile hides one in a title', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: runner.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			const card = await openDashboard(page);

			// The regression this replaces: copy a touch screen cannot show.
			await expect(card.locator('[title]')).toHaveCount(0);

			const trigger = page.getByRole('button', { name: 'About CTL (fitness)' });
			await expect(trigger).toHaveAttribute('aria-expanded', 'false');
			await expect(page.getByTestId('metric-definition-ctl')).toHaveCount(0);

			await trigger.focus();
			await page.keyboard.press('Enter');

			const definition = page.getByTestId('metric-definition-ctl');
			await expect(definition).toBeVisible();
			await expect(definition).toHaveText(CTL_DEFINITION);
			await expect(trigger).toHaveAttribute('aria-expanded', 'true');

			// Written into a live region the page mounted before the press, so
			// a screen reader announces it rather than finding it by accident.
			const region = page.locator(`[id="${await trigger.getAttribute('aria-controls')}"]`);
			await expect(region).toHaveAttribute('role', 'status');
			await expect(region).toContainText(CTL_DEFINITION);

			// Inside the viewport, not clipped off an edge of the card.
			const box = await definition.boundingBox();
			const viewport = page.viewportSize();
			expect(box).not.toBeNull();
			expect(viewport).not.toBeNull();
			expect(box!.x).toBeGreaterThanOrEqual(0);
			expect(box!.x + box!.width).toBeLessThanOrEqual(viewport!.width);

			await page.keyboard.press('Escape');
			await expect(definition).toHaveCount(0);
			await expect(trigger).toBeFocused();
			await expect(trigger).toHaveAttribute('aria-expanded', 'false');

			// Space is the other key a button answers to.
			await page.keyboard.press('Space');
			await expect(page.getByTestId('metric-definition-ctl')).toBeVisible();
		} finally {
			await ctx.close();
		}
	});

	test('a term named mid-sentence renders in place, with its disclosure', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: runner.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			await openDashboard(page);
			const footnote = page.getByTestId('race-predictor').locator('.footnote');
			// The placeholder is filled, never shown, and the name sits inside
			// the sentence rather than trailing after it.
			await expect(footnote).toContainText('Predicted with the Riegel formula');
			await expect(footnote).not.toContainText('{term}');

			await footnote.getByRole('button', { name: 'About Riegel formula' }).click();
			await expect(page.getByTestId('metric-definition-riegel')).toHaveText(
				/Riegel formula — a standard way to predict your time/
			);
		} finally {
			await ctx.close();
		}
	});

	test('a tap on a phone opens a definition and a tap elsewhere closes it', async ({ browser }) => {
		const ctx = await browser.newContext({
			storageState: runner.storageStatePath,
			viewport: { width: 390, height: 844 },
			hasTouch: true,
			isMobile: true,
		});
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();
		try {
			const card = await openDashboard(page);

			const trigger = page.getByTestId('metric-info-tsb');
			await trigger.scrollIntoViewIfNeeded();
			const hit = await trigger.boundingBox();
			expect(hit).not.toBeNull();
			// WCAG 2.2 target size (2.5.8): 24 CSS px in both directions.
			expect(hit!.width).toBeGreaterThanOrEqual(24);
			expect(hit!.height).toBeGreaterThanOrEqual(24);

			await trigger.tap();
			const definition = page.getByTestId('metric-definition-tsb');
			await expect(definition).toBeVisible();
			await expect(definition).toHaveText(/Form \(TSB\) — fitness minus fatigue/);

			const box = await definition.boundingBox();
			expect(box).not.toBeNull();
			expect(box!.x).toBeGreaterThanOrEqual(0);
			expect(box!.x + box!.width).toBeLessThanOrEqual(390);

			await card.locator('.fitness-advice').tap();
			await expect(definition).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});
