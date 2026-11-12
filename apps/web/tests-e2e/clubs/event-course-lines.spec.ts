import { expect, test } from '../fixtures/test';

import { readCount, readRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent, insertRoute } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Course start and finish lines (#1305, clubs.md § Courses, decisions § 2390).
 *
 * USER_A owns richmond-run-club. Each test seeds its own event through the
 * service role and deletes it afterwards (the cascade takes the courses, the
 * race session and its frozen copy).
 *
 * The lines are driven through the numeric inputs, the path that works without
 * a pointer and without the map loading; dragging on the map moves the same
 * values through the same RPC.
 *
 *   - a routeless course: place a finish line by typing its position, turn it,
 *     then remove it;
 *   - a course with a route: its derived line shows as from the route, a line
 *     turned against the route is warned about, and Reset to route clears both;
 *   - Arm runs the preflight: a course with no finish line and no finish point
 *     opens the dialog with a warning, Arm anyway arms and freezes the course.
 *
 * The preflight's errors exist only for a self-timed race (#1306), so no Host
 * GO event can reach one; course_gates.test.ts covers every row of the table.
 */

const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

async function insertCourse(eventId: string, routeId: string | null): Promise<string> {
	const { data, error } = await getAdminClient()
		.from('event_courses')
		.insert({ event_id: eventId, route_id: routeId, name: 'Main', distance_m: 5000, sort_order: 0 })
		.select('id')
		.single();
	if (error || !data) throw new Error(`insertCourse failed: ${error?.message ?? 'no row'}`);
	return data.id as string;
}

test.describe('/clubs/[slug]/events/[id] — course start and finish lines', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;
	let routeId: string | null = null;
	test.afterEach(async () => {
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch {
				/* best-effort */
			}
			eventId = null;
		}
		if (routeId) {
			await getAdminClient().from('routes').delete().eq('id', routeId);
			routeId = null;
		}
	});

	async function openEditor(page: import('@playwright/test').Page, title: string) {
		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('edit-event').click();
		const modal = page.locator('.modal', { hasText: 'Edit event' });
		await expect(modal).toBeVisible({ timeout: 5_000 });
		const editor = modal.getByTestId('course-gate-editor');
		await expect(editor).toBeVisible({ timeout: 10_000 });
		return editor;
	}

	test('place, turn and remove a line on a routeless course', async ({ page }) => {
		const title = `e2e-course-lines-place ${Date.now()}`;
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});
		const courseId = await insertCourse(eventId, null);
		const editor = await openEditor(page, title);

		await expect(editor.getByTestId('course-gate-finish-source')).toHaveText('None');
		await editor.getByTestId('course-gate-finish-place').click();
		await editor.getByTestId('course-gate-lat').fill('37.5407');
		await editor.getByTestId('course-gate-lng').fill('-77.436');
		await editor.getByTestId('course-gate-bearing').fill('0');
		await editor.getByTestId('course-gate-width-number').fill('20');
		await editor.getByTestId('course-gate-apply').click();

		await expect(editor.getByTestId('course-gate-finish-source')).toHaveText('Placed by an organiser', {
			timeout: 10_000
		});
		const placed = await readRow(
			'course after place',
			getAdminClient()
				.from('event_courses')
				.select('finish_gate_lat, finish_gate_lng, finish_gate_bearing_deg, finish_gate_half_width_m, finish_gate_source')
				.eq('id', courseId)
				.single()
		);
		expect(placed).toEqual({
			finish_gate_lat: 37.5407,
			finish_gate_lng: -77.436,
			finish_gate_bearing_deg: 0,
			finish_gate_half_width_m: 20,
			finish_gate_source: 'organiser'
		});

		// Turn it to face east. The width field left cleared keeps the last
		// width rather than saving the default (#1358).
		await editor.getByTestId('course-gate-width-number').fill('');
		await editor.getByTestId('course-gate-bearing').fill('90');
		await editor.getByTestId('course-gate-apply').click();
		await expect
			.poll(
				async () =>
					await readRow(
						'course after turn',
						getAdminClient()
							.from('event_courses')
							.select('finish_gate_bearing_deg, finish_gate_half_width_m')
							.eq('id', courseId)
							.single()
					),
				{ timeout: 10_000 }
			)
			.toEqual({ finish_gate_bearing_deg: 90, finish_gate_half_width_m: 20 });
		await expect(editor.getByTestId('course-gate-width-number')).toHaveValue('20');

		// A routeless course has no route to go back to, so reset removes it.
		await editor.getByTestId('course-gate-finish-reset').click();
		await expect(editor.getByTestId('course-gate-finish-source')).toHaveText('None', { timeout: 10_000 });
		const removed = await readRow(
			'course after remove',
			getAdminClient().from('event_courses').select('finish_gate_source').eq('id', courseId).single()
		);
		expect(removed.finish_gate_source).toBeNull();
	});

	test('a line turned against the route is warned about, and Reset to route restores it', async ({
		page
	}) => {
		const title = `e2e-course-lines-route ${Date.now()}`;
		routeId = await insertRoute({
			user_id: USER_A.id,
			name: `e2e course lines ${Date.now()}`,
			// Due north, 1.1 km.
			waypoints: [
				{ lat: 37.53, lng: -77.44 },
				{ lat: 37.535, lng: -77.44 },
				{ lat: 37.54, lng: -77.44 }
			],
			distance_m: 1112
		});
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});
		const courseId = await insertCourse(eventId, routeId);
		const editor = await openEditor(page, title);

		await expect(editor.getByTestId('course-gate-start-source')).toHaveText('From the route');
		await expect(editor.getByTestId('course-gate-finish-source')).toHaveText('From the route');

		// Edit the finish line (the default) and point it south, against the route.
		await editor.getByTestId('course-gate-finish-edit').click();
		await editor.getByTestId('course-gate-bearing').fill('180');
		await editor.getByTestId('course-gate-apply').click();
		await expect(editor.getByTestId('course-gate-finish-source')).toHaveText('Placed by an organiser', {
			timeout: 10_000
		});
		await expect(editor.getByTestId('course-gate-warning-against_route')).toBeVisible({ timeout: 10_000 });

		await editor.getByTestId('course-gate-finish-reset').click();
		await expect(editor.getByTestId('course-gate-finish-source')).toHaveText('From the route', {
			timeout: 10_000
		});
		await expect(editor.getByTestId('course-gate-warning-against_route')).toHaveCount(0);
		const reset = await readRow(
			'course after reset',
			getAdminClient()
				.from('event_courses')
				.select('finish_gate_source, finish_gate_lat, finish_gate_lng')
				.eq('id', courseId)
				.single()
		);
		expect(reset).toEqual({ finish_gate_source: 'derived', finish_gate_lat: 37.54, finish_gate_lng: -77.44 });
	});

	test('Arm warns about a course with no finish, and Arm anyway freezes it', async ({ page }) => {
		const title = `e2e-course-lines-preflight ${Date.now()}`;
		const startsAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: startsAt
		});
		await insertCourse(eventId, null);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({ timeout: 10_000 });
		await page.getByRole('button', { name: 'Arm race' }).click();

		const dialog = page.getByTestId('race-preflight-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await expect(dialog.getByTestId('race-preflight-warning')).toContainText(
			'Main: no finish line and no finish point'
		);
		await expect(dialog.getByTestId('race-preflight-error')).toHaveCount(0);

		await dialog.getByTestId('race-preflight-arm').click();
		await expect(page.getByRole('button', { name: 'GO', exact: true })).toBeVisible({ timeout: 10_000 });

		const admin = getAdminClient();
		const session = await readRow(
			'armed session',
			admin
				.from('race_sessions')
				.select('status, courses_frozen_at')
				.eq('event_id', eventId)
				.single()
		);
		expect(session.status).toBe('armed');
		expect(session.courses_frozen_at).not.toBeNull();
		expect(
			await readCount(
				'frozen courses',
				admin.from('race_session_courses').select('course_id', { count: 'exact', head: true }).eq('event_id', eventId)
			)
		).toBe(1);
	});
});
