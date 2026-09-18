import { expect, type Page } from '@playwright/test';

/**
 * Open `/dashboard`'s "Training load" expander if this account is rendering
 * it (#905 workstream 1, decisions § 1656).
 *
 * At the `simple` disclosure level the VO₂ max / CTL / ATL / TSB snapshot and
 * the fitness-fatigue-form curve are FOLDED into a named `<details>` rather
 * than dropped, and an account derives `simple` from a low run count — which
 * is exactly the shape a spec builds when it creates a saga user and inserts
 * three runs. Such a spec is asserting something about the snapshot's
 * CONTENTS, not about where the page puts it, so it opens the fold and
 * carries on; a spec that means to assert the fold itself is
 * `dashboard/disclosure.spec.ts`.
 *
 * Idempotent, and silent when the account renders no expander at all
 * (`standard` / `full`), so a caller needs no branch of its own.
 */
export async function expandTrainingLoad(page: Page): Promise<void> {
	// Wait for whichever shape this account renders before asking which one it
	// is: a `count()` taken straight after `goto` is 0 because the SPA has not
	// hydrated, and a helper that reads that as "no expander" silently does
	// nothing — which is a helper that never fires on the exact account it
	// exists for.
	await page
		.locator('[data-testid="training-load-disclosure"], .fitness-card')
		.first()
		.waitFor({ state: 'attached', timeout: 15_000 })
		.catch(() => {});
	const disclosure = page.getByTestId('training-load-disclosure');
	if ((await disclosure.count()) === 0) return;
	if (await disclosure.evaluate((el) => (el as HTMLDetailsElement).open)) return;
	await disclosure.locator('summary').click();
	await expect(disclosure).toHaveJSProperty('open', true);
}
