import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { seedDateToLive } from '../fixtures/plan-today';
import { USER_A } from '../fixtures/users';
import { readMaybeRow } from '../fixtures/db-read';
import { acceptCookieConsent, planSectionsOpen } from '../fixtures/helpers';

/**
 * WorkoutEditor's Mark done / Skip (#1186 round 2).
 *
 * Both close the editor. They used to do it without saving, so a runner who
 * typed a note and then pressed Mark as done lost the note with no warning.
 * They now save the edits first. Their failure used to read "Update failed",
 * unannounced; it now names the action, frames a localized cause (never the
 * raw database text) and is a live alert. The eight pace minute / second
 * boxes each carry an accessible name.
 */

const SYDNEY_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

async function intervalWorkout() {
	const admin = getAdminClient();
	const { data: weeks } = await admin
		.from('plan_weeks')
		.select('id')
		.eq('plan_id', SYDNEY_HALF_PLAN_ID);
	const weekIds = (weeks ?? []).map((w) => (w as { id: string }).id);
	const row = await readMaybeRow(
		'plan_workouts by week_id+scheduled_date',
		admin
			.from('plan_workouts')
			.select('id, notes, completed_at, manually_completed, skipped_at')
			.in('week_id', weekIds)
			.eq('scheduled_date', await seedDateToLive('2026-04-14'))
			.maybeSingle()
	);
	expect(row).not.toBeNull();
	const before = row as {
		id: string;
		notes: string | null;
		completed_at: string | null;
		manually_completed: boolean;
		skipped_at: string | null;
	};
	const restore = async () => {
		await admin
			.from('plan_workouts')
			.update({
				notes: before.notes,
				completed_at: before.completed_at,
				manually_completed: before.manually_completed,
				skipped_at: before.skipped_at
			})
			.eq('id', before.id);
	};
	return { admin, id: before.id, restore };
}

async function openIntervalEditor(page: import('@playwright/test').Page) {
	await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
	const intervalDay = page
		.locator('.weeks .week .day:not(.completed) .day-link', { hasText: /Interval/ })
		.first();
	await expect(intervalDay).toBeVisible({ timeout: 10_000 });
	await intervalDay.click();
	const modal = page.locator('.modal');
	await expect(modal).toBeVisible({ timeout: 5_000 });
	return modal;
}

test.describe('WorkoutEditor Mark done / Skip', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context, planSectionsOpen(USER_A.id));
	});

	test('Mark as done saves an unsaved note first', async ({ page }) => {
		const { admin, id, restore } = await intervalWorkout();
		try {
			const modal = await openIntervalEditor(page);
			await modal.locator('textarea').fill('legs heavy, cut the last rep');
			await modal.getByRole('button', { name: 'Mark as done' }).click();
			await expect(modal).toHaveCount(0, { timeout: 10_000 });

			const { data } = await admin
				.from('plan_workouts')
				.select('notes, manually_completed')
				.eq('id', id)
				.maybeSingle();
			const row = data as { notes: string | null; manually_completed: boolean } | null;
			expect(row?.notes).toBe('legs heavy, cut the last rep');
			expect(row?.manually_completed).toBe(true);
		} finally {
			await restore();
		}
	});

	test('a failed Skip names the action, hides the raw error and is announced', async ({ page }) => {
		const { restore } = await intervalWorkout();
		try {
			const modal = await openIntervalEditor(page);
			await page.route('**/rest/v1/plan_workouts*', async (route) => {
				const body = route.request().postData() ?? '';
				if (route.request().method() === 'PATCH' && body.includes('skipped_at')) {
					await route.fulfill({
						status: 400,
						contentType: 'application/json',
						body: JSON.stringify({
							code: '23514',
							message: 'new row violates check constraint "plan_workouts_skip_check"'
						})
					});
				} else {
					await route.continue();
				}
			});
			await modal.getByRole('button', { name: 'Skip' }).click();

			const alert = modal.getByRole('alert');
			await expect(alert).toContainText("Couldn't skip the workout", { timeout: 10_000 });
			await expect(alert).not.toContainText('violates');
			await expect(modal).toBeVisible();
		} finally {
			await page.unroute('**/rest/v1/plan_workouts*');
			await restore();
		}
	});

	test('every pace minute and second box has an accessible name', async ({ page }) => {
		const modal = await openIntervalEditor(page);
		const paceInputs = modal.locator('.pace-row input');
		const count = await paceInputs.count();
		expect(count).toBeGreaterThanOrEqual(6);
		for (let i = 0; i < count; i++) {
			await expect(paceInputs.nth(i)).toHaveAccessibleName(/.+/);
		}
		await expect(modal.getByRole('spinbutton', { name: 'Target pace from, minutes' })).toBeVisible();
		await expect(modal.getByRole('spinbutton', { name: 'Rep pace, seconds' })).toBeVisible();
	});
});
