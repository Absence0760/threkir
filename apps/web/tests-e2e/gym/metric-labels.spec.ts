import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * RPE and 1RM on the gym surfaces carry their definitions (#902 section 2).
 *
 * Both were bare column headers and field captions with no expansion
 * anywhere. The builder is the hard case: a caption that labels an input
 * cannot hold a button inside its `<label>` without the button taking the
 * label's click and its accessible name, so `<MetricLabel labelFor>` renders
 * the label and the disclosure side by side. This pins that the definition
 * opens, that each input keeps its plain name, and that pressing the caption
 * still focuses its input.
 */
test.describe('gym metric labels', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the routine builder explains RPE and 1RM without breaking the fields they caption', async ({
		page,
	}) => {
		await page.goto('/gym/routines/new');
		await page.getByTestId('routine-set-rpe').first().waitFor({ timeout: 15_000 });

		// The column header's disclosure.
		await page.getByRole('button', { name: 'About RPE' }).first().click();
		await expect(page.getByTestId('metric-definition-rpe')).toContainText(
			'rate of perceived exertion'
		);
		await page.keyboard.press('Escape');
		await expect(page.getByTestId('metric-definition-rpe')).toHaveCount(0);

		// The input still announces the name alone, not "RPE About RPE".
		await expect(page.getByTestId('routine-set-rpe').first()).toHaveAccessibleName('RPE');

		// A percentage-of-1RM progression: the caption is the input's label.
		await page.locator('details.advanced summary').first().click();
		await page.getByTestId('routine-progression').first().selectOption('percent_cycle');
		const percent = page.getByTestId('routine-progression-percent').first();
		await expect(percent).toHaveAccessibleName('% of 1RM');
		await page.locator('label.metric-caption', { hasText: '% of 1RM' }).first().click();
		await expect(percent).toBeFocused();

		await page.getByRole('button', { name: 'About % of 1RM' }).first().click();
		await expect(page.getByTestId('metric-definition-e1rm')).toContainText('one-rep max');
	});

	test('the records page names the estimate in its subtitle, with a disclosure', async ({ page }) => {
		await page.goto('/gym/records');
		const subtitle = page.locator('.head-sub');
		await expect(subtitle).toContainText('Each card leads with your best estimated one-rep max (1RM).');
		await expect(subtitle).not.toContainText('{term}');
		await subtitle.getByRole('button', { name: /^About estimated one-rep max/ }).click();
		await expect(page.getByTestId('metric-definition-e1rm')).toBeVisible();
	});
});
