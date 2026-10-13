import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { readCount, readRow, readRows } from '../fixtures/db-read';
import { deleteEvent } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * A class event carries one of its club's gym routine templates
 * (decisions § 1869).
 *
 * The organiser (USER_A, Richmond's owner) creates a class in the editor and
 * picks the seeded club template "Club Strength — Lower Body"; picking it
 * clears the session-plan picker, because a class carries one or the other.
 * The event page lists the routine. A member attendee (USER_B) then logs the
 * class and the composer arrives pre-filled from the routine's planned sets,
 * and saving it writes the attendee's OWN workout without cloning the
 * template into their routine library.
 */

const CLUB_TEMPLATE_ID = '61918001-0000-0000-0000-000000000001';
const CLUB_TEMPLATE_TITLE = 'Club Strength — Lower Body';

test.describe('class event — attached gym routine', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdEvents: string[] = [];
	const createdWorkouts: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of createdWorkouts.splice(0)) {
			try {
				await admin.from('gym_workouts').delete().eq('id', id);
			} catch (_) {
				/* best-effort */
			}
		}
		for (const id of createdEvents.splice(0)) {
			try {
				await deleteEvent(id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('an organiser attaches a club routine; an attendee logs the class pre-filled from it', async ({
		page,
		browser
	}) => {
		const stamp = Date.now();
		const title = `e2e-routine-class ${stamp}`;
		const discipline = `Strength ${stamp}`;
		const dayIso = new Date(stamp + 7 * 24 * 3600 * 1000).toISOString().slice(0, 10);

		await page.goto('/clubs/richmond-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });
		await page.getByRole('button', { name: /New event/ }).click();
		const modal = page.locator('.modal', { hasText: 'New event' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		await modal.getByRole('radio', { name: 'Class', exact: true }).click();
		const routinePicker = modal.getByTestId('gym-routine-picker');
		await expect(routinePicker.locator('option', { hasText: CLUB_TEMPLATE_TITLE })).toHaveCount(1, {
			timeout: 10_000
		});
		await routinePicker.selectOption({ label: CLUB_TEMPLATE_TITLE });
		await expect(modal.getByTestId('session-plan-picker')).toHaveValue('');

		await modal.getByPlaceholder('Sunday long run').fill(title);
		await modal.getByPlaceholder(/Vinyasa yoga/).fill(discipline);
		await modal.locator('input[type="date"]').first().fill(dayIso);
		await modal.locator('input[type="time"]').first().fill('18:00');
		await modal.getByRole('button', { name: /Create event/ }).click();
		await expect(modal).toHaveCount(0, { timeout: 10_000 });

		await page.getByRole('tab', { name: /^Events/ }).click();
		const eventRow = page.locator('a[href*="/events/"]', { hasText: title });
		await expect(eventRow).toBeVisible({ timeout: 10_000 });
		const href = (await eventRow.getAttribute('href')) ?? '';
		const eventId = href.match(/\/events\/([0-9a-f-]+)$/)![1];
		createdEvents.push(eventId);

		const admin = getAdminClient();
		const row = await readRow(
			'events by id',
			admin.from('events').select('gym_routine_id, session_plan_id').eq('id', eventId).single()
		);
		expect(row.gym_routine_id).toBe(CLUB_TEMPLATE_ID);
		expect(row.session_plan_id).toBeNull();

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		const routineCard = page.getByTestId('class-routine');
		await expect(routineCard.getByText(CLUB_TEMPLATE_TITLE)).toBeVisible({ timeout: 10_000 });
		await expect(routineCard.getByText('Back Squat')).toBeVisible();

		const routinesBefore = await readCount(
			'USER_B routines',
			admin
				.from('gym_routines')
				.select('id', { count: 'exact', head: true })
				.eq('author_id', USER_B.id)
		);

		const ctx = await browser.newContext({ storageState: USER_B.storageStatePath });
		try {
			const attendee = await ctx.newPage();
			await attendee.goto(`/clubs/richmond-run-club/events/${eventId}`);
			await expect(attendee.getByTestId('class-routine').getByText('Back Squat')).toBeVisible({
				timeout: 10_000
			});
			await attendee.getByTestId('log-as-workout').click();
			const gymModal = attendee.locator('.modal', { hasText: 'Log this as a workout' });
			await expect(gymModal).toBeVisible({ timeout: 5_000 });

			await expect(gymModal.getByPlaceholder('e.g. Push day')).toHaveValue(discipline);
			const names = gymModal.getByPlaceholder('Exercise name');
			await expect(names.first()).toHaveValue('Back Squat');
			await expect(names).toHaveCount(4);
			await expect(gymModal.getByLabel('Reps', { exact: true }).first()).toHaveValue('5');

			await gymModal.getByRole('button', { name: 'Save workout' }).click();
			await expect(gymModal).toHaveCount(0, { timeout: 10_000 });
		} finally {
			await ctx.close();
		}

		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('gym_workouts')
						.select('id')
						.eq('user_id', USER_B.id)
						.eq('title', discipline);
					for (const w of data ?? []) {
						if (!createdWorkouts.includes(w.id as string)) createdWorkouts.push(w.id as string);
					}
					return (data ?? []).length;
				},
				{ timeout: 10_000 }
			)
			.toBe(1);

		const sets = await readRows(
			'gym_sets of the logged class',
			admin
				.from('gym_sets')
				.select('exercise_name, reps')
				.eq('workout_id', createdWorkouts[0])
				.order('set_index', { ascending: true })
		);
		expect(sets[0]).toEqual({ exercise_name: 'Back Squat', reps: 5 });

		// The template was read, not cloned into the attendee's library.
		const routinesAfter = await readCount(
			'USER_B routines',
			admin
				.from('gym_routines')
				.select('id', { count: 'exact', head: true })
				.eq('author_id', USER_B.id)
		);
		expect(routinesAfter).toBe(routinesBefore);
	});
});
