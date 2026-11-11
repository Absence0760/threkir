import { expect, test } from '../fixtures/test';

import { readRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, deleteRun, insertEvent, insertRaceSession, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Re-time a race result from the run's stored track (#1307 M11).
 *
 * USER_A owns richmond-run-club. Each test seeds an event with one 1 km
 * course, a Host GO race session that finished an hour ago, the race's frozen
 * course with a start line and a finish line 1 km due east of it, and a run
 * whose track walks straight through both lines at 4 m/s. The race_retime
 * unit suite covers the lock rule, the clock basis and every refusal; this
 * spec pins the panel's wiring end to end: it reads the frozen course, shows
 * the current result beside the one the track gives, confirms, and writes the
 * crossings the server derives the times from.
 */

const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const START = { lat: 51.4613, lng: -0.3037 };
const METRES_PER_DEG_LAT = (6371008.8 * Math.PI) / 180;
const metresPerDegLng = METRES_PER_DEG_LAT * Math.cos((START.lat * Math.PI) / 180);

function east(m: number): { lat: number; lng: number } {
	return { lat: START.lat, lng: START.lng + m / metresPerDegLng };
}

test.describe('/runs/[id] — re-time a race result from the track', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;
	let runId: string | null = null;
	test.afterEach(async () => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch {
				/* best-effort */
			}
			runId = null;
		}
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch {
				/* best-effort */
			}
			eventId = null;
		}
	});

	test('a DNF is replaced by the line-timed result the track gives', async ({ page }) => {
		const admin = getAdminClient();
		const goMs = Math.floor(Date.now() / 1000) * 1000 - 2 * 3600 * 1000;
		const instanceStart = new Date(goMs).toISOString();
		const title = `e2e-race-retime ${Date.now()}`;
		eventId = await insertEvent({
			club_id: RICHMOND_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			starts_at: instanceStart
		});
		const { data: course, error: courseErr } = await admin
			.from('event_courses')
			.insert({ event_id: eventId, name: 'Main', distance_m: 1000, sort_order: 0 })
			.select('id')
			.single();
		if (courseErr || !course) throw new Error(`course insert failed: ${courseErr?.message}`);
		await insertRaceSession({
			event_id: eventId,
			instance_start: instanceStart,
			status: 'finished',
			started_at: instanceStart,
			finished_at: new Date(goMs + 3600 * 1000).toISOString(),
			started_by: USER_A.id,
			is_auto_approve: true
		});
		const finish = east(1000);
		const { error: frozenErr } = await admin.from('race_session_courses').upsert(
			{
				event_id: eventId,
				instance_start: instanceStart,
				course_id: course.id,
				start_gate_lat: START.lat,
				start_gate_lng: START.lng,
				start_gate_bearing_deg: 90,
				start_gate_half_width_m: 15,
				finish_gate_lat: finish.lat,
				finish_gate_lng: finish.lng,
				finish_gate_bearing_deg: 90,
				finish_gate_half_width_m: 15,
				finish_lat: finish.lat,
				finish_lng: finish.lng,
				distance_m: 1000,
				finish_line_self_cross: false
			},
			{ onConflict: 'event_id,instance_start,course_id' }
		);
		if (frozenErr) throw new Error(`frozen course upsert failed: ${frozenErr.message}`);

		// From 30 m behind the start line at GO + 10 s, 4 m/s due east, a fix
		// every 2 s: the start crossing falls at GO + 17.5 s and the finish
		// crossing at GO + 267.5 s, so gun 267 s (4:27) and chip 250 s (4:10).
		const pressMs = goMs + 10_000;
		const track = Array.from({ length: 141 }, (_, i) => {
			const metres = -30 + 8 * i;
			return {
				...east(metres),
				ts: new Date(pressMs + 2000 * i).toISOString(),
				distM: 8 * i
			};
		});
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(pressMs).toISOString(),
			duration_s: 280,
			distance_m: 1120,
			track
		});
		const { error: linkErr } = await admin.from('runs').update({ event_id: eventId }).eq('id', runId);
		if (linkErr) throw new Error(`run link failed: ${linkErr.message}`);
		const { error: dnfErr } = await admin.from('event_results').insert({
			event_id: eventId,
			instance_start: instanceStart,
			user_id: USER_A.id,
			course_id: course.id,
			distance_m: 1000,
			duration_s: 0,
			finisher_status: 'dnf',
			finish_method: 'host'
		});
		if (dnfErr) throw new Error(`dnf insert failed: ${dnfErr.message}`);

		await page.goto(`/runs/${runId}`);
		const panel = page.getByTestId('race-retime');
		await expect(panel).toBeVisible({ timeout: 15_000 });
		await expect(panel.getByTestId('race-retime-state')).toHaveAttribute('data-state', 'ready');
		await expect(panel.getByTestId('race-retime-current-status')).toHaveText('Did not finish');
		await expect(panel.getByTestId('race-retime-new-gun')).toHaveText('4:27');
		await expect(panel.getByTestId('race-retime-new-chip')).toHaveText('4:10');
		await expect(panel.getByTestId('race-retime-new-start')).toHaveText('Start line');
		await expect(panel.getByTestId('race-retime-new-finish')).toHaveText('Finish line');
		await expect(panel.getByTestId('race-retime-clock-device')).toBeVisible();

		await panel.getByTestId('race-retime-action').click();
		const dialog = page.getByRole('dialog');
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Replace result' }).click();
		await expect(panel.getByTestId('race-retime-state')).toContainText('Result re-timed from your track.', {
			timeout: 10_000
		});

		const row = await readRow(
			'event_results for the re-timed runner',
			admin
				.from('event_results')
				.select('finisher_status, finish_method, start_detection, finish_detection, gun_time_s, chip_time_s, run_id')
				.eq('event_id', eventId)
				.eq('user_id', USER_A.id)
				.single()
		);
		expect(row).toMatchObject({
			finisher_status: 'finished',
			finish_method: 'auto',
			start_detection: 'gate',
			finish_detection: 'gate',
			gun_time_s: 267,
			chip_time_s: 250,
			run_id: runId
		});
	});
});
