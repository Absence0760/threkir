import { expect, test } from '@playwright/test';

import { readCount, readRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import {
	deleteEvent,
	insertEvent,
	insertRacePings,
	insertRaceSession
} from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Multi-course races (clubs.md § Live race mode, decisions § 1842).
 *
 * USER_A owns richmond-run-club (race director + event organiser); USER_B is
 * an active member. Each test seeds its own event with two courses through the
 * service role and deletes it afterwards — the cascade takes the courses,
 * attendees, race session, pings and results with it.
 *
 *   - the event editor saves a main course plus an added one,
 *   - a member must pick a course before "I'm in" on a two-course event, and
 *     the pick lands on their RSVP,
 *   - the results card ranks each course separately, with the gun / chip split
 *     and the host-edited badge,
 *   - End states how many racers it will mark DNF and files those DNFs,
 *   - an organiser's time edit lands and is badged host-edited, and on a
 *     chip-only row it gives the row no gun time,
 *   - removing a course racers picked drops their pick to no course,
 *   - End with nobody out on course states no DNF count and files none,
 *   - a one-course event asks for no pick and files the RSVP on that course,
 *   - the spectator page shows one finisher board per course, and splits its
 *     on-course board by each runner's RSVP'd course the same way.
 */

const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

async function insertCourses(
	eventId: string,
	courses: Array<{ name: string; distance_m: number }>
): Promise<string[]> {
	const { data, error } = await getAdminClient()
		.from('event_courses')
		.insert(courses.map((c, i) => ({ event_id: eventId, ...c, sort_order: i })))
		.select('id, sort_order');
	if (error || !data) throw new Error(`insertCourses failed: ${error?.message ?? 'no rows'}`);
	return [...data].sort((a, b) => a.sort_order - b.sort_order).map((r) => r.id as string);
}

async function insertResult(row: {
	event_id: string;
	instance_start: string;
	user_id: string;
	course_id: string;
	duration_s: number;
	distance_m: number;
	gun_time_s?: number | null;
	chip_time_s?: number | null;
	finish_method?: 'auto' | 'manual' | 'host' | null;
	finisher_status?: 'finished' | 'dnf' | 'dns';
}): Promise<void> {
	const { error } = await getAdminClient()
		.from('event_results')
		.insert({ finisher_status: 'finished', ...row });
	if (error) throw new Error(`insertResult failed: ${error.message}`);
}

test.describe('/clubs/[slug]/events/[id] — race courses (organiser)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;
	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch {
				/* best-effort */
			}
			eventId = null;
		}
	});

	test('the editor saves the main course and an added course', async ({ page }) => {
		const title = `e2e-race-courses-create ${Date.now()}`;
		const dayIso = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString().slice(0, 10);

		await page.goto('/clubs/richmond-run-club');
		await page.getByRole('button', { name: /New event/ }).click();
		const modal = page.locator('.modal', { hasText: 'New event' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		await modal.getByPlaceholder('Sunday long run').fill(title);
		await modal.locator('input[type="date"]').first().fill(dayIso);
		await modal.locator('input[type="time"]').first().fill('07:30');

		await modal.getByTestId('event-add-course').click();
		await modal.getByTestId('event-main-course-name').fill('Half');
		await modal.getByTestId('event-course-name').fill('10K');
		await modal.getByTestId('event-course-distance').fill('10');

		await modal.getByRole('button', { name: /Create event/ }).click();
		await expect(modal).toHaveCount(0, { timeout: 10_000 });

		const admin = getAdminClient();
		const { data: ev } = await admin.from('events').select('id').eq('title', title).single();
		eventId = ev?.id ?? null;
		expect(eventId).not.toBeNull();
		const courses = await readRows(
			'event_courses by event',
			admin.from('event_courses').select('name, sort_order').eq('event_id', eventId!).order('sort_order')
		);
		expect(courses.map((c) => c.name)).toEqual(['Half', '10K']);
	});

	test('results rank per course, with the gun/chip split and the host-edited badge', async ({
		page
	}) => {
		const startsAt = new Date(Date.now() - 2 * 3600 * 1000).toISOString();
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-race-courses-results ${Date.now()}`,
			starts_at: startsAt
		});
		const [tenK, fiveK] = await insertCourses(eventId, [
			{ name: '10K', distance_m: 10000 },
			{ name: '5K', distance_m: 5000 }
		]);
		await insertRaceSession({
			event_id: eventId,
			instance_start: startsAt,
			status: 'finished',
			started_at: startsAt,
			finished_at: new Date(Date.now() - 3600 * 1000).toISOString(),
			started_by: USER_A.id
		});
		// The 5K finisher is faster, so a single combined board would rank the
		// 10K winner second.
		await insertResult({
			event_id: eventId,
			instance_start: startsAt,
			user_id: USER_A.id,
			course_id: tenK,
			duration_s: 2400,
			distance_m: 10000,
			gun_time_s: 2400,
			chip_time_s: 2390,
			finish_method: 'auto'
		});
		await insertResult({
			event_id: eventId,
			instance_start: startsAt,
			user_id: USER_B.id,
			course_id: fiveK,
			duration_s: 1500,
			distance_m: 5000,
			gun_time_s: 1500,
			finish_method: 'host'
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);

		const titles = page.getByTestId('course-board-title');
		await expect(titles).toHaveCount(2, { timeout: 10_000 });
		await expect(titles.nth(0)).toContainText('10K');
		await expect(titles.nth(1)).toContainText('5K');

		const boards = page.getByTestId('course-board');
		await expect(boards.nth(0).locator('.rank').first()).toHaveText('1');
		await expect(boards.nth(1).locator('.rank').first()).toHaveText('1');
		await expect(boards.nth(0).locator('.time-split')).toContainText('chip 39:50');
		await expect(boards.nth(1).getByTestId('finish-method-badge')).toHaveText('Host edited');
	});

	test('End states how many racers it marks DNF, and files the DNF', async ({ page }) => {
		const startsAt = new Date(Date.now() - 3600 * 1000).toISOString();
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-race-courses-end ${Date.now()}`,
			starts_at: startsAt
		});
		const [tenK] = await insertCourses(eventId, [
			{ name: '10K', distance_m: 10000 },
			{ name: '5K', distance_m: 5000 }
		]);
		await getAdminClient().from('event_attendees').insert({
			event_id: eventId,
			instance_start: startsAt,
			user_id: USER_B.id,
			status: 'going',
			course_id: tenK
		});
		await insertRaceSession({
			event_id: eventId,
			instance_start: startsAt,
			status: 'running',
			started_at: startsAt,
			started_by: USER_A.id
		});
		await insertRacePings({
			event_id: eventId,
			instance_start: startsAt,
			runners: [
				{
					user_id: USER_B.id,
					points: [{ lat: -37.82, lng: 144.98, distance_m: 4200, elapsed_s: 1500 }]
				}
			]
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await page.getByRole('button', { name: 'End race' }).click();
		const dialog = page.getByRole('dialog');
		await expect(dialog).toContainText('1 racer who started has no result and will be marked DNF', {
			timeout: 10_000
		});
		await dialog.getByRole('button', { name: 'End race' }).click();

		await expect
			.poll(
				async () => {
					const { data } = await getAdminClient()
						.from('event_results')
						.select('finisher_status, finish_method, course_id')
						.eq('event_id', eventId!)
						.eq('user_id', USER_B.id)
						.maybeSingle();
					return data ? `${data.finisher_status}/${data.finish_method}/${data.course_id}` : null;
				},
				{ timeout: 10_000 }
			)
			.toBe(`dnf/host/${tenK}`);
	});

	test("an organiser's time edit lands and is badged host-edited", async ({ page }) => {
		const startsAt = new Date(Date.now() - 2 * 3600 * 1000).toISOString();
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-race-courses-edit ${Date.now()}`,
			starts_at: startsAt
		});
		const [tenK] = await insertCourses(eventId, [{ name: '10K', distance_m: 10000 }]);
		await insertRaceSession({
			event_id: eventId,
			instance_start: startsAt,
			status: 'finished',
			started_at: startsAt,
			finished_at: new Date(Date.now() - 3600 * 1000).toISOString(),
			started_by: USER_A.id
		});
		await insertResult({
			event_id: eventId,
			instance_start: startsAt,
			user_id: USER_B.id,
			course_id: tenK,
			duration_s: 2500,
			distance_m: 10000,
			gun_time_s: 2500,
			finish_method: 'auto'
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await page.getByTestId('edit-result').first().click();
		const panel = page.getByTestId('edit-result-panel');
		await expect(panel).toBeVisible();
		await panel.getByTestId('edit-result-time').fill('45:00');
		await panel.getByTestId('edit-result-save').click();
		await expect(panel).toHaveCount(0, { timeout: 10_000 });

		await expect(page.getByTestId('finish-method-badge')).toHaveText('Host edited');
		const data = await readRow(
			'edited result',
			getAdminClient()
				.from('event_results')
				.select('duration_s, gun_time_s, finish_method')
				.eq('event_id', eventId)
				.eq('user_id', USER_B.id)
				.single()
		);
		expect(data).toEqual({ duration_s: 2700, gun_time_s: 2700, finish_method: 'host' });
	});

	test('a host edit on a chip-only result keeps it chip-only', async ({ page }) => {
		const startsAt = new Date(Date.now() - 2 * 3600 * 1000).toISOString();
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-race-courses-edit-chip ${Date.now()}`,
			starts_at: startsAt
		});
		const [tenK] = await insertCourses(eventId, [{ name: '10K', distance_m: 10000 }]);
		await insertRaceSession({
			event_id: eventId,
			instance_start: startsAt,
			status: 'finished',
			started_at: startsAt,
			finished_at: new Date(Date.now() - 3600 * 1000).toISOString(),
			started_by: USER_A.id
		});
		// A web "Submit my time" during a race: chip time only, no gun reading.
		await insertResult({
			event_id: eventId,
			instance_start: startsAt,
			user_id: USER_B.id,
			course_id: tenK,
			duration_s: 2500,
			distance_m: 10000,
			chip_time_s: 2500,
			gun_time_s: null,
			finish_method: 'manual'
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await page.getByTestId('edit-result').first().click();
		const panel = page.getByTestId('edit-result-panel');
		await panel.getByTestId('edit-result-time').fill('45:00');
		await panel.getByTestId('edit-result-save').click();
		await expect(panel).toHaveCount(0, { timeout: 10_000 });

		await expect(page.getByTestId('finish-method-badge')).toHaveText('Host edited');
		const data = await readRow(
			'edited chip-only result',
			getAdminClient()
				.from('event_results')
				.select('duration_s, gun_time_s, chip_time_s, finish_method')
				.eq('event_id', eventId)
				.eq('user_id', USER_B.id)
				.single()
		);
		expect(data).toEqual({
			duration_s: 2700,
			gun_time_s: null,
			chip_time_s: 2500,
			finish_method: 'host'
		});
	});

	test('removing a course racers picked drops their pick to no course and keeps the rest', async ({
		page
	}) => {
		const title = `e2e-race-courses-remove ${Date.now()}`;
		const startsAt = new Date(Date.now() + 3 * 24 * 3600 * 1000).toISOString();
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: startsAt,
			distance_m: 10000
		});
		const [, half, kids] = await insertCourses(eventId, [
			{ name: 'Main', distance_m: 10000 },
			{ name: 'Half', distance_m: 21097 },
			{ name: 'Kids', distance_m: 2000 }
		]);
		const { error: rsvpErr } = await getAdminClient().from('event_attendees').insert({
			event_id: eventId,
			instance_start: startsAt,
			user_id: USER_B.id,
			status: 'going',
			course_id: half
		});
		if (rsvpErr) throw new Error(`rsvp insert failed: ${rsvpErr.message}`);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 10_000
		});
		await page.getByTestId('edit-event').click();
		const modal = page.locator('.modal', { hasText: 'Edit event' });
		await expect(modal.getByTestId('event-course-row')).toHaveCount(2, { timeout: 10_000 });
		await modal.getByRole('button', { name: 'Remove Half' }).click();
		await expect(modal.getByTestId('event-course-row')).toHaveCount(1);
		await modal.getByRole('button', { name: 'Save changes' }).click();
		await expect(modal).toHaveCount(0, { timeout: 10_000 });

		const admin = getAdminClient();
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('event_courses')
						.select('id, name, sort_order')
						.eq('event_id', eventId!)
						.order('sort_order');
					return (data ?? []).map((c) => `${c.name}@${c.sort_order}`);
				},
				{ timeout: 10_000 }
			)
			.toEqual(['Main@0', 'Kids@1']);
		const kept = await readRow(
			'surviving course',
			admin.from('event_courses').select('id').eq('id', kids).single()
		);
		expect(kept.id, 'the surviving course was updated in place, not re-created').toBe(kids);
		const rsvp = await readRow(
			'rsvp on the removed course',
			admin
				.from('event_attendees')
				.select('status, course_id')
				.eq('event_id', eventId)
				.eq('user_id', USER_B.id)
				.single()
		);
		expect(rsvp).toEqual({ status: 'going', course_id: null });
	});

	test('End with nobody out on course states no DNF count and files none', async ({ page }) => {
		const startsAt = new Date(Date.now() - 3600 * 1000).toISOString();
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-race-courses-end-zero ${Date.now()}`,
			starts_at: startsAt
		});
		const [tenK] = await insertCourses(eventId, [
			{ name: '10K', distance_m: 10000 },
			{ name: '5K', distance_m: 5000 }
		]);
		// Going, but never pinged the race: not a racer who started.
		await getAdminClient().from('event_attendees').insert({
			event_id: eventId,
			instance_start: startsAt,
			user_id: USER_B.id,
			status: 'going',
			course_id: tenK
		});
		await insertRaceSession({
			event_id: eventId,
			instance_start: startsAt,
			status: 'running',
			started_at: startsAt,
			started_by: USER_A.id
		});

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		const panel = page.locator('.race-panel');
		await expect(panel.getByRole('button', { name: 'End race' })).toBeVisible({ timeout: 10_000 });
		// A started race is ended, never cancelled: the server refuses running
		// -> cancelled, and the phone offers the same (decisions § R7RACE-3).
		await expect(panel.getByRole('button', { name: /Cancel/ })).toHaveCount(0);
		await page.getByRole('button', { name: 'End race' }).click();
		const dialog = page.getByRole('dialog');
		await expect(dialog).toContainText('End the race?', { timeout: 10_000 });
		await expect(dialog).not.toContainText('DNF');
		await dialog.getByRole('button', { name: 'End race' }).click();

		const admin = getAdminClient();
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('race_sessions')
						.select('status')
						.eq('event_id', eventId!)
						.single();
					return data?.status ?? null;
				},
				{ timeout: 10_000 }
			)
			.toBe('finished');
		const results = await readCount(
			'results after End',
			admin.from('event_results').select('id', { count: 'exact', head: true }).eq('event_id', eventId)
		);
		expect(results).toBe(0);
	});
});

test.describe('/clubs/[slug]/events/[id] — race courses (member RSVP)', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let eventId: string | null = null;
	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch {
				/* best-effort */
			}
			eventId = null;
		}
	});

	test("a two-course event asks for a course before I'm in, and keeps the pick", async ({
		page
	}) => {
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-race-courses-rsvp ${Date.now()}`,
			starts_at: new Date(Date.now() + 3 * 24 * 3600 * 1000).toISOString()
		});
		const [, fiveK] = await insertCourses(eventId, [
			{ name: '10K', distance_m: 10000 },
			{ name: '5K', distance_m: 5000 }
		]);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		const goingButton = page.getByRole('button', { name: "I'm in" });
		await goingButton.click();
		await expect(page.getByRole('alert')).toContainText('Pick your course first.');

		await page.getByTestId('rsvp-course-select').selectOption(fiveK);
		await goingButton.click();

		await expect
			.poll(
				async () => {
					const { data } = await getAdminClient()
						.from('event_attendees')
						.select('status, course_id')
						.eq('event_id', eventId!)
						.eq('user_id', USER_B.id)
						.maybeSingle();
					return data ? `${data.status}/${data.course_id}` : null;
				},
				{ timeout: 10_000 }
			)
			.toBe(`going/${fiveK}`);
	});

	test('a one-course event asks for no pick and files the RSVP on that course', async ({
		page
	}) => {
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-race-courses-single ${Date.now()}`,
			starts_at: new Date(Date.now() + 3 * 24 * 3600 * 1000).toISOString()
		});
		const [only] = await insertCourses(eventId, [{ name: '10K', distance_m: 10000 }]);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		const goingButton = page.getByRole('button', { name: "I'm in" });
		await expect(goingButton).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('rsvp-course-select')).toHaveCount(0);
		await goingButton.click();
		await expect(page.getByText('Pick your course first.')).toHaveCount(0);

		await expect
			.poll(
				async () => {
					const { data } = await getAdminClient()
						.from('event_attendees')
						.select('status, course_id')
						.eq('event_id', eventId!)
						.eq('user_id', USER_B.id)
						.maybeSingle();
					return data ? `${data.status}/${data.course_id}` : null;
				},
				{ timeout: 10_000 }
			)
			.toBe(`going/${only}`);
	});
});

test.describe('/live/event/[id]/[instance] — one finisher board per course', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('each course gets its own titled board', async ({ page }) => {
		const startsAt = new Date(Date.now() - 2 * 3600 * 1000).toISOString();
		const eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-race-courses-live ${Date.now()}`,
			starts_at: startsAt
		});
		try {
			const [tenK, fiveK] = await insertCourses(eventId, [
				{ name: '10K', distance_m: 10000 },
				{ name: '5K', distance_m: 5000 }
			]);
			await insertRaceSession({
				event_id: eventId,
				instance_start: startsAt,
				status: 'finished',
				started_at: startsAt,
				finished_at: new Date(Date.now() - 3600 * 1000).toISOString(),
				started_by: USER_A.id
			});
			await insertResult({
				event_id: eventId,
				instance_start: startsAt,
				user_id: USER_A.id,
				course_id: tenK,
				duration_s: 2400,
				distance_m: 10000,
				finish_method: 'manual'
			});
			await insertResult({
				event_id: eventId,
				instance_start: startsAt,
				user_id: USER_B.id,
				course_id: fiveK,
				duration_s: 1500,
				distance_m: 5000
			});

			await page.goto(`/live/event/${eventId}/${encodeURIComponent(startsAt)}`);

			const titles = page.getByTestId('live-course-title');
			await expect(titles).toHaveCount(2, { timeout: 10_000 });
			await expect(titles.nth(0)).toContainText('10K');
			await expect(titles.nth(1)).toContainText('5K');
			await expect(page.getByTestId('live-course-board')).toHaveCount(2);
			await expect(page.getByTestId('live-finish-method')).toHaveText('Manual');
		} finally {
			await deleteEvent(eventId);
		}
	});

	test("the on-course board splits by each runner's course", async ({ page }) => {
		const startsAt = new Date(Date.now() - 30 * 60 * 1000).toISOString();
		const eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-race-courses-live-oncourse ${Date.now()}`,
			starts_at: startsAt
		});
		try {
			const [tenK, fiveK] = await insertCourses(eventId, [
				{ name: '10K', distance_m: 10000 },
				{ name: '5K', distance_m: 5000 }
			]);
			const { error: rsvpErr } = await getAdminClient()
				.from('event_attendees')
				.insert(
					[
						{ user_id: USER_A.id, course_id: tenK },
						{ user_id: USER_B.id, course_id: fiveK }
					].map((r) => ({ ...r, event_id: eventId, instance_start: startsAt, status: 'going' }))
				);
			if (rsvpErr) throw new Error(`rsvp insert failed: ${rsvpErr.message}`);
			await insertRaceSession({
				event_id: eventId,
				instance_start: startsAt,
				status: 'running',
				started_at: startsAt,
				started_by: USER_A.id
			});
			// The 5K runner is further along, so a combined board would put the
			// 10K runner second.
			await insertRacePings({
				event_id: eventId,
				instance_start: startsAt,
				runners: [
					{
						user_id: USER_A.id,
						points: [{ lat: -37.82, lng: 144.98, distance_m: 3000, elapsed_s: 900 }]
					},
					{
						user_id: USER_B.id,
						points: [{ lat: -37.82, lng: 144.985, distance_m: 4200, elapsed_s: 1200 }]
					}
				]
			});

			await page.goto(`/live/event/${eventId}/${encodeURIComponent(startsAt)}`);

			const titles = page.getByTestId('live-oncourse-title');
			await expect(titles).toHaveCount(2, { timeout: 10_000 });
			await expect(titles.nth(0)).toContainText('10K');
			await expect(titles.nth(1)).toContainText('5K');
			const boards = page.getByTestId('live-oncourse-board');
			await expect(boards).toHaveCount(2);
			for (const i of [0, 1]) {
				await expect(boards.nth(i).locator('.runner')).toHaveCount(1);
				await expect(boards.nth(i).locator('.pos')).toHaveText('1');
			}
		} finally {
			await deleteEvent(eventId);
		}
	});
});
