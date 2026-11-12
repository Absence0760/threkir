import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';
import { readRow, readRows } from '../fixtures/db-read';

/**
 * /gym/routines/library — the public gym-routine library (migration
 * 20270224_001, docs/features/gym_programming.md).
 *
 * Covers: an owner publishes a personal routine to the public library and
 * unpublishes it (set_gym_routine_public); a different signed-in user browses
 * the library, previews a public routine's planned sets, and adopts (clones) it
 * into their own routine list (clone_gym_routine_template public branch); a
 * verified club's routine carries the Official badge there.
 *
 * Each run uses a unique title so rows never collide in the shared seed DB and
 * cleans up its own backend rows.
 */
test.describe('/gym/routines/library — publish, browse, preview, adopt', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('owner publishes + unpublishes a routine to/from the public library', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E Public Toggle ${stamp}`;

		const { data: r } = await admin
			.from('gym_routines')
			.insert({ author_id: USER_A.id, title, exercise_count: 0 })
			.select('id')
			.single();
		const routineId = r!.id as string;

		try {
			await page.goto(`/gym/routines/${routineId}`);
			// Publish.
			await page.getByTestId('routine-toggle-public').click();
			await expect(page.getByTestId('routine-public-badge')).toBeVisible({ timeout: 10_000 });
			let after = await readRow(
				'gym_routines by id',
				admin
					.from('gym_routines')
					.select('is_public_template')
					.eq('id', routineId)
					.single()
			);
			expect(after.is_public_template).toBe(true);

			// Unpublish.
			await page.getByTestId('routine-toggle-public').click();
			await expect(page.getByTestId('routine-public-badge')).toHaveCount(0, { timeout: 10_000 });
			after = await readRow(
				'gym_routines by id',
				admin
					.from('gym_routines')
					.select('is_public_template')
					.eq('id', routineId)
					.single()
			);
			expect(after.is_public_template).toBe(false);
		} finally {
			await admin.from('gym_routines').delete().eq('id', routineId);
		}
	});

	test('a signed-in user browses, previews, and adopts a public routine', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E Public Lib ${stamp}`;
		const exercise = `E2E Squat ${stamp}`;

		// Seed a public template owned by USER_B with one exercise + two sets.
		const { data: r } = await admin
			.from('gym_routines')
			.insert({ author_id: USER_B.id, title, exercise_count: 1, is_public_template: true })
			.select('id')
			.single();
		const templateId = r!.id as string;
		const { data: ex } = await admin
			.from('gym_routine_exercises')
			.insert({
				routine_id: templateId,
				exercise_name: exercise,
				exercise_key: exercise.trim().toLowerCase(),
				position: 0,
			})
			.select('id')
			.single();
		await admin.from('gym_routine_sets').insert([
			{ routine_exercise_id: ex!.id, set_index: 0, target_reps_min: 5, target_weight_kg: 100 },
			{ routine_exercise_id: ex!.id, set_index: 1, target_reps_min: 5, target_weight_kg: 100 },
		]);

		let adoptedId: string | null = null;
		try {
			// Browse: the library lists the public template (search narrows to it).
			await page.goto('/gym/routines/library');
			await page.getByRole('searchbox').fill(title);
			await expect(page.getByTestId('gym-library-list')).toBeVisible({ timeout: 10_000 });
			await page.getByRole('link', { name: new RegExp(title) }).click();

			// Preview: the planned exercise + sets render.
			await expect(page.getByTestId('gym-library-adopt')).toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.exercise-name', { hasText: exercise })).toBeVisible();

			// The set-preview table exposes column headers for screen readers (WCAG 1.3.1).
			const setTable = page.locator('.set-table').first();
			await expect(setTable.getByRole('columnheader', { name: 'Set type' })).toBeVisible();
			await expect(setTable.getByRole('columnheader', { name: 'Target reps' })).toBeVisible();

			// Adopt → lands on the new personal routine detail.
			await page.getByTestId('gym-library-adopt').click();
			await expect(page).toHaveURL(/\/gym\/routines\/[0-9a-f-]+$/, { timeout: 10_000 });
			await expect(page.getByTestId('routine-exercises')).toContainText(exercise);

			// A new personal (club-less, non-public) routine is owned by USER_A.
			const clones = await readRows(
				'gym_routines by author_id+title',
				admin
					.from('gym_routines')
					.select('id, club_id, is_public_template, exercise_count')
					.eq('author_id', USER_A.id)
					.eq('title', title)
			);
			expect(clones.length).toBe(1);
			adoptedId = clones![0].id as string;
			expect(clones![0].club_id).toBeNull();
			expect(clones![0].is_public_template).toBe(false);

			const clonedEx = await readRows(
				'gym_routine_exercises by routine_id',
				admin
					.from('gym_routine_exercises')
					.select('id, exercise_key')
					.eq('routine_id', adoptedId)
			);
			expect(clonedEx.length).toBe(1);
			const clonedSets = await readRows(
				'gym_routine_sets by routine_exercise_id',
				admin
					.from('gym_routine_sets')
					.select('target_weight_kg')
					.eq('routine_exercise_id', clonedEx![0].id)
			);
			expect(clonedSets.length).toBe(2);
			expect(Number(clonedSets![0].target_weight_kg)).toBe(100);
		} finally {
			if (adoptedId) await admin.from('gym_routines').delete().eq('id', adoptedId);
			await admin.from('gym_routines').delete().eq('id', templateId);
		}
	});

	// A verified club's routine reaches the library through the official
	// catalogue load (issue #1190, migration 20271211000002), which writes as
	// the service role; the library and its preview carry the Official badge,
	// and a personal routine beside it does not.
	test('a verified club routine reads as official in the library and its preview', async ({ page }) => {
		const admin = getAdminClient();
		const clubId = crypto.randomUUID();
		const stamp = Date.now();
		const official = `E2E Official Lib ${stamp}`;
		const personal = `E2E Personal Lib ${stamp}`;

		const club = await admin.from('clubs').insert({
			id: clubId,
			owner_id: USER_B.id,
			name: `E2E Official Gym ${stamp}`,
			slug: `e2e-official-gym-${stamp}`,
			is_public: true,
		});
		if (club.error) throw club.error;
		const verified = await admin.from('clubs').update({ is_verified: true }).eq('id', clubId);
		if (verified.error) throw verified.error;
		const routines = await admin
			.from('gym_routines')
			.insert([
				{ author_id: USER_B.id, club_id: clubId, title: official, exercise_count: 0, is_public_template: true },
				{ author_id: USER_B.id, title: personal, exercise_count: 0, is_public_template: true },
			])
			.select('id, title');
		if (routines.error) throw routines.error;
		const officialId = routines.data.find((r) => r.title === official)!.id;

		try {
			await page.goto('/gym/routines/library');
			await page.getByRole('searchbox').fill(`${stamp}`);
			const list = page.getByTestId('gym-library-list');
			const officialCard = list.getByRole('link', { name: new RegExp(official) });
			const personalCard = list.getByRole('link', { name: new RegExp(personal) });
			await expect(officialCard).toBeVisible({ timeout: 10_000 });
			await expect(personalCard).toBeVisible();
			await expect(officialCard.getByTestId('official-badge')).toBeVisible();
			await expect(personalCard.getByTestId('official-badge')).toHaveCount(0);

			await officialCard.click();
			await expect(page).toHaveURL(new RegExp(`/gym/routines/library/${officialId}$`));
			await expect(page.getByRole('heading', { level: 1 }).getByTestId('official-badge')).toBeVisible({
				timeout: 10_000,
			});
		} finally {
			await admin.from('gym_routines').delete().in('id', routines.data.map((r) => r.id));
			await admin.from('clubs').delete().eq('id', clubId);
		}
	});
});
