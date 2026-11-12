import { expect, test } from '../fixtures/test';

import { readRows } from '../fixtures/db-read';
import { acceptCookieConsent } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers } from '../fixtures/saga-users';

/**
 * The plan wizard's week outline puts a pace field beside distances in the
 * runner's unit. The pace used to be per km whatever the unit, and stored as
 * typed: a mile runner who corrected a session to 8:51 got 8:51/km, which is
 * 14:15/mi. A saga user, so the mile preference touches no one else.
 */
test('a mile runner types an outline pace per mile and it is stored per km', async ({
	browser
}) => {
	const [runner] = await createSagaUsers(1, { displayNames: ['Mile Outline Runner'] });
	const admin = getAdminClient();
	await admin.from('user_profiles').update({ preferred_unit: 'mi' }).eq('id', runner.id);
	const ctx = await browser.newContext({ storageState: runner.storageStatePath });
	await acceptCookieConsent(ctx);
	try {
		const page = await ctx.newPage();
		await page.goto('/plans/new');
		await expect(page.getByRole('heading', { level: 1, name: 'Build a training plan' })).toBeVisible({
			timeout: 15_000
		});
		const editor = page.locator('.plan-editor');
		await editor.getByPlaceholder('Autumn half marathon').fill('e2e mile outline');
		await editor.locator('select').first().selectOption('distance_5k');

		const firstWeek = editor.locator('.week-item').first();
		await expect(firstWeek).toBeVisible({ timeout: 10_000 });
		await firstWeek.locator('.week-row').click();
		await expect(firstWeek.locator('.week-editor')).toBeVisible();

		const paceField = firstWeek
			.locator('label.wo-field', { hasText: 'Pace (mm:ss per mi)' })
			.locator('input:not([disabled])')
			.first();
		await paceField.fill('8:51');

		await editor.getByRole('button', { name: /Create plan/ }).click();
		await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
		const planId = page.url().match(/\/plans\/([0-9a-f-]+)$/)![1];

		const weeks = await readRows(
			'plan_weeks by plan_id',
			admin.from('plan_weeks').select('id').eq('plan_id', planId)
		);
		const rows = await readRows(
			'plan_workouts by week_id',
			admin
				.from('plan_workouts')
				.select('target_pace_sec_per_km')
				.in(
					'week_id',
					weeks.map((w) => (w as { id: string }).id)
				)
		);
		const paces = rows.map((r) => (r as { target_pace_sec_per_km: number | null }).target_pace_sec_per_km);
		// 8:51/mi is 531 s/mi, 329.95 s/km, stored as 330.
		expect(paces).toContain(330);
		expect(paces).not.toContain(531);
	} finally {
		await ctx.close();
		await admin.from('training_plans').delete().eq('user_id', runner.id);
		await deleteSagaUsers([runner]);
	}
});
