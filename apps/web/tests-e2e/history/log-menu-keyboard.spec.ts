import { expect, test } from '../fixtures/test';

import { browserDayAt } from '../fixtures/dates';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * The /history Log menu keeps the ARIA menu-button contract it shares with
 * the dashboard's Add or import menu (`MenuButton`): ArrowDown / ArrowUp on
 * the trigger open it on the first / last item, Tab or Shift+Tab out closes
 * it, and a click on the trigger while it is open closes it rather than
 * closing and reopening.
 *
 * Workout and Food are offered only while Gym and Nutrition are surfaced,
 * which for a runner with no explicit choice means having logged one of each.
 * A clean saga user carries the one lift and one meal this spec plants: the
 * seed user's meals are not a fixed precondition, because the /nutrition
 * specs clear USER_A's recent food_log, and a shard that runs one of them
 * first leaves this menu at two items.
 */
test.describe('/history — Log menu keyboard and focus', () => {
	let user: SagaUser;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { healthConsent: true, displayNames: ['Log Menu Keyboard'] });
		const admin = getAdminClient();
		const at = browserDayAt(-1, 18);
		const lift = await admin
			.from('gym_workouts')
			.insert({ user_id: user.id, title: 'Log Menu Lift', started_at: at, last_modified_at: at });
		expect(lift.error).toBeNull();
		const meal = await admin
			.from('food_log')
			.insert({ user_id: user.id, started_at: browserDayAt(-1, 12), item_name: 'Log Menu Meal' });
		expect(meal.error).toBeNull();
	});

	test.afterAll(async () => {
		if (user) await deleteSagaUsers([user]).catch(() => {});
	});

	test('the Log menu opens, cycles and closes like a menu button', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();
		try {
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
		} finally {
			await ctx.close();
		}
	});
});
