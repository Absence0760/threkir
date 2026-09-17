import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /gym — Routines and Sessions sat as two sibling header buttons, and nothing
 * in either word said that one is a strength template (gym_programming.md)
 * and the other a timed yoga / pilates sequence (session_planner.md) (#902 §7).
 * They now carry the names the create hub already uses — Gym routines, Session
 * plans — and a visible one-line description each, in a labelled row of
 * destinations under the header. The data-presence gates are unchanged:
 * gym.spec.ts and records.spec.ts pin those through the same test ids.
 */

test.describe('/gym planning destinations', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('routines and session plans are named apart and say what each holds', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const now = new Date().toISOString();
		const workout = await admin
			.from('gym_workouts')
			.insert({ user_id: USER_A.id, title: `E2E destinations ${stamp}`, started_at: now, last_modified_at: now })
			.select('id')
			.single();
		if (workout.error) throw new Error(workout.error.message);
		const plan = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title: `E2E destinations ${stamp}` })
			.select('id')
			.single();
		if (plan.error) throw new Error(plan.error.message);

		try {
			await page.goto('/gym');

			const nav = page.getByRole('navigation', { name: 'Routines, session plans and records' });
			const routines = nav.getByRole('link', { name: 'Gym routines', exact: true });
			const sessions = nav.getByRole('link', { name: 'Session plans', exact: true });

			await expect(routines).toBeVisible({ timeout: 10_000 });
			await expect(routines).toHaveAttribute('href', '/gym/routines');
			await expect(routines).toHaveAccessibleDescription(/strength workouts.*sets, reps and load/);
			await expect(routines.getByText(/strength workouts/)).toBeVisible();

			await expect(sessions).toBeVisible();
			await expect(sessions).toHaveAttribute('href', '/sessions');
			await expect(sessions).toHaveAccessibleDescription(/yoga, pilates and mobility/);
			await expect(sessions.getByText(/yoga, pilates and mobility/)).toBeVisible();

			await expect(page.locator('.page-header').getByRole('link')).toHaveCount(0);
			await expect(page.getByRole('link', { name: 'Routines', exact: true })).toHaveCount(0);
			await expect(page.getByRole('link', { name: 'Sessions', exact: true })).toHaveCount(0);
		} finally {
			await admin.from('session_plans').delete().eq('id', (plan.data as { id: string }).id);
			await admin.from('gym_workouts').delete().eq('id', (workout.data as { id: string }).id);
		}
	});
});
