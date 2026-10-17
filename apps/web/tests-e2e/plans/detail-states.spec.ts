import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';
import { readMaybeRow, readRows } from '../fixtures/db-read';
import { SYDNEY_HALF_PLAN_ID } from '../fixtures/plan-today';
import { browserDate } from '../fixtures/dates';

/**
 * /plans/[id] — the states a plan workout and the plan itself can be in:
 * a past, unfinished workout reads as missed (dashed, not like an upcoming
 * one), and a coach-assigned plan says who assigned it. Issue #1186.
 */

test.describe('/plans/[id] — workout and plan states', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a past workout that was neither done nor skipped reads as missed', async ({ page }) => {
		const admin = getAdminClient();
		const weeks = await readRows(
			'plan_weeks by plan_id',
			admin.from('plan_weeks').select('id').eq('plan_id', SYDNEY_HALF_PLAN_ID)
		);
		const today = browserDate();
		const missed = await readRows(
			'past open plan_workouts',
			admin
				.from('plan_workouts')
				.select('id, scheduled_date')
				.in(
					'week_id',
					(weeks as { id: string }[]).map((w) => w.id)
				)
				.neq('kind', 'rest')
				.lt('scheduled_date', today)
				.is('completed_run_id', null)
				.eq('manually_completed', false)
				.is('skipped_at', null)
		);
		// The seed slides the plan onto a window that is already under way.
		expect(missed.length, 'the seeded plan has a past open workout').toBeGreaterThan(0);

		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		const missedDays = page.locator('.weeks .week .day[data-status="missed"]');
		await expect(missedDays.first()).toBeVisible({ timeout: 10_000 });
		await expect(missedDays.first().locator('.day-link')).toHaveAttribute('aria-label', /, missed/);
		await expect(missedDays.first()).toHaveCSS('border-left-style', 'dashed');
	});

	test('a coach-assigned plan names the coach and links to coaching', async ({ page }) => {
		const admin = getAdminClient();
		const profile = await readMaybeRow(
			'coach display name',
			admin.from('user_profiles').select('display_name').eq('id', USER_B.id).maybeSingle()
		);
		const coachName = (profile as { display_name: string | null } | null)?.display_name;
		expect(coachName).toBeTruthy();

		await admin
			.from('training_plans')
			.update({ assigned_by_coach_id: USER_B.id })
			.eq('id', SYDNEY_HALF_PLAN_ID);
		try {
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
			const chip = page.getByTestId('assigned-by-coach');
			await expect(chip).toContainText(`Assigned by ${coachName}`, { timeout: 10_000 });
			await expect(chip).toHaveAttribute('href', '/coaching');
		} finally {
			await admin
				.from('training_plans')
				.update({ assigned_by_coach_id: null })
				.eq('id', SYDNEY_HALF_PLAN_ID);
		}
	});

	test('the runner\'s own plan has no assigned-by chip', async ({ page }) => {
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('assigned-by-coach')).toHaveCount(0);
	});
});
