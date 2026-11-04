import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * The /history Log menu keeps the ARIA menu-button contract it shares with
 * the dashboard's Add or import menu (`MenuButton`): ArrowDown / ArrowUp on
 * the trigger open it on the first / last item, Tab or Shift+Tab out closes
 * it, and a click on the trigger while it is open closes it rather than
 * closing and reopening. USER_A's seeded lifts and meals put all three
 * actions in the menu. Read-only: nothing is logged.
 */
test.describe('/history — Log menu keyboard and focus', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the Log menu opens, cycles and closes like a menu button', async ({ page }) => {
		await page.goto('/history');
		const trigger = page.getByRole('button', { name: 'Log', exact: true });
		await expect(trigger).toBeVisible({ timeout: 15_000 });
		const menu = page.getByRole('menu');
		const run = menu.getByRole('menuitem', { name: 'Log run' });
		const food = menu.getByRole('menuitem', { name: 'Log food' });

		await test.step('ArrowDown opens on the first item, arrows cycle', async () => {
			await trigger.focus();
			await page.keyboard.press('ArrowDown');
			await expect(trigger).toHaveAttribute('aria-expanded', 'true');
			await expect(run).toBeFocused();
			await page.keyboard.press('ArrowUp');
			await expect(food).toBeFocused();
			await page.keyboard.press('Home');
			await expect(run).toBeFocused();
			await page.keyboard.press('End');
			await expect(food).toBeFocused();
			await page.keyboard.press('Escape');
			await expect(menu).toHaveCount(0);
			await expect(trigger).toBeFocused();
		});

		await test.step('ArrowUp opens on the last item; Tab out closes it', async () => {
			await page.keyboard.press('ArrowUp');
			await expect(food).toBeFocused();
			await page.keyboard.press('Tab');
			await expect(menu).toHaveCount(0);
			await expect(trigger).toHaveAttribute('aria-expanded', 'false');
		});

		await test.step('Shift+Tab from the first item closes it back on the trigger', async () => {
			await trigger.focus();
			await page.keyboard.press('ArrowDown');
			await expect(run).toBeFocused();
			await page.keyboard.press('Shift+Tab');
			await expect(menu).toHaveCount(0);
			await expect(trigger).toBeFocused();
		});

		await test.step('a click on the trigger while it is open closes it', async () => {
			await trigger.click();
			await expect(run).toBeFocused();
			await trigger.click();
			await expect(menu).toHaveCount(0);
			await expect(trigger).toHaveAttribute('aria-expanded', 'false');
			await expect(trigger).toBeFocused();
		});
	});
});
