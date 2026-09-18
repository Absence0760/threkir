import { expect, test } from '@playwright/test';

import { setUserSetting } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /dashboard — the progressive-disclosure level (issue #905 workstream 1).
 *
 * At `simple` the training-load block (VO₂ max / CTL / ATL / TSB + the
 * fitness-fatigue-form curve) is FOLDED into a named expander rather than
 * removed, and whether it was opened is remembered against the account — a
 * disclosure that forgets is one the runner re-opens on every visit, which is
 * worse than not folding at all. At `standard` / `full` the page is unchanged.
 *
 * Resets the two keys in `finally` so a failure here cannot leave the seed
 * account folded up for every other dashboard spec.
 */
test.describe('/dashboard — progressive disclosure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('simple folds the training load away, and remembers being opened', async ({ page }) => {
		try {
			await setUserSetting(USER_A.id, 'disclosure_level', 'simple');
			await setUserSetting(USER_A.id, 'dashboard_training_load_expanded', null);

			await page.goto('/dashboard');
			const disclosure = page.getByTestId('training-load-disclosure');
			await expect(disclosure).toBeVisible({ timeout: 10_000 });
			// Folded, not dropped: the section is named, and its contents are
			// one click away rather than gone.
			await expect(disclosure).toHaveJSProperty('open', false);
			await expect(disclosure).toContainText(/training load/i);
			const chartHeading = page.getByRole('heading', { name: /Fitness, Fatigue & Form/i });
			await expect(chartHeading).toBeHidden();

			await disclosure.locator('summary').click();
			await expect(disclosure).toHaveJSProperty('open', true);
			await expect(chartHeading).toBeVisible();

			// Remembered against the account, not the tab: a fresh load of the
			// page finds it open.
			await page.goto('/dashboard');
			await expect(page.getByTestId('training-load-disclosure')).toHaveJSProperty('open', true, {
				timeout: 10_000,
			});

			// And closing it is remembered the same way round.
			await page.getByTestId('training-load-disclosure').locator('summary').click();
			await expect(page.getByTestId('training-load-disclosure')).toHaveJSProperty('open', false);
			await page.goto('/dashboard');
			await expect(page.getByTestId('training-load-disclosure')).toHaveJSProperty('open', false, {
				timeout: 10_000,
			});
		} finally {
			await setUserSetting(USER_A.id, 'disclosure_level', null);
			await setUserSetting(USER_A.id, 'dashboard_training_load_expanded', null);
		}
	});

	test('full leaves the page exactly as it was — no expander at all', async ({ page }) => {
		try {
			await setUserSetting(USER_A.id, 'disclosure_level', 'full');
			await page.goto('/dashboard');
			await expect(page.getByRole('heading', { name: /Fitness, Fatigue & Form/i })).toBeVisible({
				timeout: 10_000,
			});
			await expect(page.getByTestId('training-load-disclosure')).toHaveCount(0);
		} finally {
			await setUserSetting(USER_A.id, 'disclosure_level', null);
		}
	});
});
