import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';
import { readMaybeRow } from '../fixtures/db-read';

/**
 * /plans/[id]/workouts/[wid] — single-workout drill-down.
 *
 * The week-grid on /plans/[id] opens an in-place WorkoutEditor modal
 * (covered in plans/detail.spec.ts). The standalone workout-detail
 * page is the alternative route — used by deep links from the coach
 * surface, and by the "View workout" path that some plan templates
 * emit. Workout IDs are auto-generated, so we query one off the
 * seeded Richmond Half plan via service-role.
 *
 * Future depth: mark complete + unlink (button + ConfirmDialog),
 * plan-workout-with-structure renders the warmup / repeats / cooldown
 * breakdown.
 */

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

test.describe('/plans/[id]/workouts/[wid]', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('renders the workout kind heading + Back-to-plan link', async ({
		page
	}) => {
		// Seed plan_workouts ids are auto-generated; pick the first
		// one off the plan's first week so we have a deterministic
		// target. The admin client bypasses RLS — fine for fixture
		// setup, never for the assertion (we navigate as runner).
		const weekRow = await readMaybeRow(
			'plan_weeks by plan_id+week_index',
			getAdminClient()
				.from('plan_weeks')
				.select('id')
				.eq('plan_id', SEED_PLAN_ID)
				.eq('week_index', 0)
				.maybeSingle()
		);
		expect(weekRow).not.toBeNull();
		const woRow = await readMaybeRow(
			'plan_workouts by week_id',
			getAdminClient()
				.from('plan_workouts')
				.select('id, kind')
				.eq('week_id', (weekRow as { id: string }).id)
				.order('scheduled_date', { ascending: true })
				.limit(1)
				.maybeSingle()
		);
		expect(woRow).not.toBeNull();
		const wo = woRow as { id: string; kind: string };

		await page.goto(`/plans/${SEED_PLAN_ID}/workouts/${wo.id}`);

		// h1 is the workout kind label (Easy / Tempo / Long / Rest /
		// Recovery, etc). The kind is a free-form string in the seed —
		// we match the page's WORKOUT_KIND_LABEL fallback (which uses
		// the raw kind when no label is mapped) by asserting the h1
		// is non-empty rather than pinning a specific label.
		const h1 = page.getByRole('heading', { level: 1 });
		await expect(h1).toBeVisible({ timeout: 10_000 });
		const text = (await h1.textContent())?.trim() ?? '';
		expect(text.length).toBeGreaterThan(0);

		// "Back to plan" link returns to /plans/[id] — proves we hit
		// the loaded-row branch, not the not-found state (which has
		// the link too, but with text "Back to plan" inside an h2
		// "Workout not found" block).
		await expect(
			page.getByRole('heading', { name: 'Workout not found' })
		).toHaveCount(0);

		// Click the back link — verifies the link href is right.
		await page.getByRole('link', { name: /Back to plan/i }).first().click();
		await expect(page).toHaveURL(new RegExp(`/plans/${SEED_PLAN_ID}$`));
	});

	test('skip + un-skip a workout from the detail page', async ({ page }) => {
		// Pick a non-rest, non-completed workout off the plan so the
		// Skip control renders (rest days + linked-run workouts don't
		// show it). Reset its skip state after so the test is idempotent.
		const admin = getAdminClient();
		const { data: weekRow } = await admin
			.from('plan_weeks')
			.select('id')
			.eq('plan_id', SEED_PLAN_ID)
			.eq('week_index', 0)
			.maybeSingle();
		const woRow = await readMaybeRow(
			'plan_workouts by week_id+kind+completed_run_id',
			admin
				.from('plan_workouts')
				.select('id, kind')
				.eq('week_id', (weekRow as { id: string }).id)
				.neq('kind', 'rest')
				.is('completed_run_id', null)
				.order('scheduled_date', { ascending: true })
				.limit(1)
				.maybeSingle()
		);
		expect(woRow).not.toBeNull();
		const wo = woRow as { id: string };

		try {
			await admin
				.from('plan_workouts')
				.update({ skipped_at: null, manually_completed: false })
				.eq('id', wo.id);

			await page.goto(`/plans/${SEED_PLAN_ID}/workouts/${wo.id}`);

			// Skip it — the "Skipped" badge + an Un-skip button appear.
			await page.getByRole('button', { name: /^Skip this workout$/i }).click();
			await expect(page.getByText('Skipped', { exact: true })).toBeVisible({
				timeout: 10_000
			});
			const unskip = page.getByRole('button', { name: /^Un-skip$/i });
			await expect(unskip).toBeVisible();

			// Server-side: skipped_at stamped.
			const afterSkip = await readMaybeRow(
				'plan_workouts by id',
				admin
					.from('plan_workouts')
					.select('skipped_at')
					.eq('id', wo.id)
					.maybeSingle()
			);
			expect((afterSkip as { skipped_at: string | null }).skipped_at).not.toBeNull();

			// Un-skip returns it to a plain to-do (the Skip button is back).
			await unskip.click();
			await expect(
				page.getByRole('button', { name: /^Skip this workout$/i })
			).toBeVisible({ timeout: 10_000 });
			const afterUnskip = await readMaybeRow(
				'plan_workouts by id',
				admin
					.from('plan_workouts')
					.select('skipped_at')
					.eq('id', wo.id)
					.maybeSingle()
			);
			expect((afterUnskip as { skipped_at: string | null }).skipped_at).toBeNull();
		} finally {
			await admin
				.from('plan_workouts')
				.update({ skipped_at: null })
				.eq('id', wo.id);
		}
	});

	test('a walk-run session reads as time, not as a dash or a bogus distance', async ({
		page
	}) => {
		// The C25K generator writes only duration_s on every step. The page
		// used to print "—" for each step and sum the seconds as metres into
		// "Total: 1.98 km". Borrow one seeded workout, give it a walk-run
		// structure, and put it back afterwards.
		const admin = getAdminClient();
		const weekRow = await readMaybeRow(
			'plan_weeks by plan_id+week_index',
			admin
				.from('plan_weeks')
				.select('id')
				.eq('plan_id', SEED_PLAN_ID)
				.eq('week_index', 0)
				.maybeSingle()
		);
		const woRow = await readMaybeRow(
			'plan_workouts by week_id',
			admin
				.from('plan_workouts')
				.select('id, structure')
				.eq('week_id', (weekRow as { id: string }).id)
				.neq('kind', 'rest')
				.order('scheduled_date', { ascending: false })
				.limit(1)
				.maybeSingle()
		);
		expect(woRow).not.toBeNull();
		const wo = woRow as { id: string; structure: unknown };

		try {
			await admin
				.from('plan_workouts')
				.update({
					structure: {
						warmup: { duration_s: 300, pace: 'easy' },
						repeats: {
							count: 8,
							duration_s: 60,
							pace_sec_per_km: 420,
							recovery_pace: 'walk',
							recovery_duration_s: 90
						},
						cooldown: { duration_s: 300, pace: 'easy' }
					}
				})
				.eq('id', wo.id);

			await page.goto(`/plans/${SEED_PLAN_ID}/workouts/${wo.id}`);

			const steps = page.locator('ol.steps');
			await expect(steps).toBeVisible({ timeout: 10_000 });
			await expect(steps.locator('.step-warmup .step-main')).toHaveText('5:00');
			await expect(steps.locator('.step-cooldown .step-main')).toHaveText('5:00');
			await expect(steps.locator('.step-work .step-main')).toHaveText('8× 1:00');
			await expect(steps.getByTestId('step-recovery')).toHaveText(/Recovery\s*1:30 walk/);
			await expect(steps).not.toContainText('—');
			// A recovery sits between reps, never after the last:
			// 300 + 8 × 60 + 7 × 90 + 300 = 1710 s.
			await expect(page.getByTestId('structure-total')).toHaveText('Total: 28:30');
			const summary = page.getByTestId('walk-run-summary');
			await expect(summary).toContainText('about 29 min');
			await expect(summary).toContainText(
				'5 min warm-up, 8 × (1 min run / 90 s walk), 5 min cool-down'
			);
		} finally {
			await admin.from('plan_workouts').update({ structure: wo.structure }).eq('id', wo.id);
		}
	});

	test('a hand-marked done workout is cleared under "Mark not done" copy', async ({
		page
	}) => {
		// With no run linked, the confirm used to say "Unlink the matched
		// run?", a run that does not exist.
		const admin = getAdminClient();
		const weekRow = await readMaybeRow(
			'plan_weeks by plan_id+week_index',
			admin
				.from('plan_weeks')
				.select('id')
				.eq('plan_id', SEED_PLAN_ID)
				.eq('week_index', 0)
				.maybeSingle()
		);
		const woRow = await readMaybeRow(
			'plan_workouts by week_id',
			admin
				.from('plan_workouts')
				.select('id')
				.eq('week_id', (weekRow as { id: string }).id)
				.neq('kind', 'rest')
				.is('completed_run_id', null)
				.order('scheduled_date', { ascending: false })
				.range(1, 1)
				.maybeSingle()
		);
		expect(woRow).not.toBeNull();
		const wo = woRow as { id: string };

		try {
			await admin
				.from('plan_workouts')
				.update({
					manually_completed: true,
					completed_at: new Date().toISOString(),
					skipped_at: null
				})
				.eq('id', wo.id);

			await page.goto(`/plans/${SEED_PLAN_ID}/workouts/${wo.id}`);
			await page.getByRole('button', { name: /^Mark not done$/ }).click();
			const dialog = page.getByRole('dialog');
			await expect(dialog.getByText('Mark not done?')).toBeVisible();
			await expect(dialog.getByText('The workout will show as not yet done.')).toBeVisible();
			await expect(dialog.getByText(/matched run/)).toHaveCount(0);
			await dialog.getByRole('button', { name: /^Mark not done$/ }).click();
			await expect(page.getByRole('button', { name: /^Skip this workout$/i })).toBeVisible({
				timeout: 10_000
			});

			const after = await readMaybeRow(
				'plan_workouts by id',
				admin.from('plan_workouts').select('manually_completed').eq('id', wo.id).maybeSingle()
			);
			expect((after as { manually_completed: boolean }).manually_completed).toBe(false);
		} finally {
			await admin
				.from('plan_workouts')
				.update({ manually_completed: false, completed_at: null })
				.eq('id', wo.id);
		}
	});

	test('not-found: visiting a missing workout id renders "Workout not found"', async ({
		page
	}) => {
		// Stale-link landing protection — same shape as /runs/[id] +
		// /routes/[id] + /plans/[id] not-found tests.
		const bogusId = '00000000-0000-0000-0000-000000000bad';
		await page.goto(`/plans/${SEED_PLAN_ID}/workouts/${bogusId}`);
		await expect(
			page.getByRole('heading', { name: /Workout not found/i })
		).toBeVisible({ timeout: 10_000 });
	});
});
