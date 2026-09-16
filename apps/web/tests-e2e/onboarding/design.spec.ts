import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /onboarding — the wizard's shell and accessibility, not its writes (those
 * are wizard.spec.ts). Walks the steps without Finish or Skip-onboarding, so
 * nothing is saved and the seeded user is left as it was.
 *
 * The wizard wears AuthShell, the same split screen as sign-up, so the pages
 * a new account walks from the landing page into the app are one design.
 */

test.describe('/onboarding design', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('wears the auth shell, and its progress tracks the step', async ({ page }) => {
		await page.setViewportSize({ width: 1440, height: 900 });
		await page.goto('/onboarding');
		await expect(page.getByRole('heading', { name: /What should we call you/i })).toBeVisible();

		await expect(page.locator('main#main-content')).toHaveCount(1);
		await expect(page.locator('aside.auth-panel')).toBeVisible();

		const progress = page.getByRole('progressbar', { name: 'Step 1 of 6' });
		await expect(progress).toHaveAttribute('aria-valuenow', '1');
		await expect(page.locator('.rail li.rail-now')).toHaveText(/Name/);

		await page.getByRole('button', { name: 'Continue' }).click();
		await expect(page.getByRole('progressbar', { name: 'Step 2 of 6' })).toHaveAttribute(
			'aria-valuenow',
			'2',
		);
		await expect(page.locator('.rail li.rail-now')).toHaveText(/Units/);
		await expect(page.locator('.rail li.rail-done')).toHaveCount(1);
	});

	test('with nothing to turn on, the wizard has no notifications step', async ({ page }) => {
		// This build has no push key, so the step would only explain that
		// nothing can be enabled. It is left out of the walk, the rail and the
		// count alike (visibleOnboardingSteps); a build that can push shows it.
		await page.setViewportSize({ width: 1440, height: 900 });
		await page.goto('/onboarding');
		await expect(page.getByRole('heading', { name: /What should we call you/i })).toBeVisible();
		await expect(page.locator('.rail li')).toHaveCount(6);
		await expect(page.locator('.rail')).not.toContainText('Notifications');
	});

	test('a step change moves focus to the new question', async ({ page }) => {
		// The card body is replaced on every step, so focus left on Continue
		// belongs to a question that is gone and a screen reader says nothing.
		await page.goto('/onboarding');
		await expect(page.getByRole('heading', { name: /What should we call you/i })).toBeVisible();

		await page.getByRole('button', { name: 'Continue' }).click();
		await expect(page.getByRole('heading', { name: /Kilometres or miles/i })).toBeFocused();

		await page.getByRole('button', { name: 'Back' }).click();
		await expect(page.getByRole('heading', { name: /What should we call you/i })).toBeFocused();
	});

	test('every single-choice group is named by its question', async ({ page }) => {
		await page.goto('/onboarding');
		await expect(page.getByRole('heading', { name: /What should we call you/i })).toBeVisible();

		const continueButton = page.getByRole('button', { name: 'Continue' });
		await continueButton.click();
		await expect(page.getByRole('radiogroup', { name: /Kilometres or miles/i })).toBeVisible();
		await continueButton.click();
		await expect(page.getByRole('radiogroup', { name: /main goal/i })).toBeVisible();
		await continueButton.click();
		await continueButton.click();
		await expect(page.getByRole('radiogroup', { name: /Who can see your runs/i })).toBeVisible();
	});

	test('reduced motion shows each new step whole on its first frame', async ({ page }) => {
		await page.emulateMedia({ reducedMotion: 'reduce' });
		await page.goto('/onboarding');
		await expect(page.getByRole('heading', { name: /What should we call you/i })).toBeVisible();
		await page.getByRole('button', { name: 'Continue' }).click();
		const opacity = await page
			.locator('.step-frame')
			.evaluate((el) => Number(getComputedStyle(el).opacity));
		expect(opacity).toBe(1);
	});

	test('on a phone the card carries the step count and nothing scrolls sideways', async ({
		page,
	}) => {
		await page.setViewportSize({ width: 390, height: 844 });
		await page.goto('/onboarding');
		await expect(page.getByRole('heading', { name: /What should we call you/i })).toBeVisible();
		await expect(page.locator('.step-count')).toBeVisible();
		await expect(page.locator('.panel-title')).toBeHidden();
		// The goal grid is the widest step.
		await page.getByRole('button', { name: 'Continue' }).click();
		await page.getByRole('button', { name: 'Continue' }).click();
		await expect(page.getByRole('radiogroup', { name: /main goal/i })).toBeVisible();
		const overflow = await page.evaluate(
			() => document.documentElement.scrollWidth - document.documentElement.clientWidth,
		);
		expect(overflow).toBeLessThanOrEqual(0);
	});
});
