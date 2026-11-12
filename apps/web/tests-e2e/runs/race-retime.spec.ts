import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { readRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, deleteRun, insertEvent, insertRaceSession, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B, type SeededUser } from '../fixtures/users';

/**
 * Re-time a race result from the run's stored track (#1307 M11).
 *
 * USER_A owns richmond-run-club and USER_B is a plain member. Each test seeds an event with one 1 km
 * course, a Host GO race session, the race's frozen course with a start line
 * and a finish line 1 km due east of it, and a run whose track walks straight
 * through both lines at 4 m/s. The race_retime unit suite covers the lock
 * rule, the clock basis and every refusal; this spec pins the panel's wiring
 * end to end: it reads the frozen course, shows the current result beside the
 * one the track gives, confirms, and writes the crossings the server derives
 * the times from — and it is not offered past the 24 h write window or to
 * anyone but the run's owner, and a failed read or write is said out loud.
 *
 * Every instant is relative to the real clock in milliseconds, never to a
 * calendar day: the 24 h window is measured against the server's `now()`.
 */

const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const START = { lat: 51.4613, lng: -0.3037 };
const METRES_PER_DEG_LAT = (6371008.8 * Math.PI) / 180;
const metresPerDegLng = METRES_PER_DEG_LAT * Math.cos((START.lat * Math.PI) / 180);
const HOUR_MS = 3600 * 1000;

function east(m: number): { lat: number; lng: number } {
	return { lat: START.lat, lng: START.lng + m / metresPerDegLng };
}

interface Seeded {
	eventId: string;
	runId: string;
	instanceStart: string;
}

/**
 * The race and the run. `finishedAgoMs` is how long before now the race
 * finished, so 25 h puts it past the write window. `dnf` files the host's
 * close-time DNF for the runner, the row a re-time replaces. The runner is
 * USER_A unless named; the race guard lets a club organiser write past the
 * window, so a test of the server's refusal runs as USER_B.
 */
async function seedRace(opts: {
	runner?: SeededUser;
	finishedAgoMs: number;
	dnf: boolean;
	runIsPublic?: boolean;
	onSeeded: (s: Seeded) => void;
}): Promise<Seeded> {
	const admin = getAdminClient();
	const runner = opts.runner ?? USER_A;
	const finishedMs = Math.floor(Date.now() / 1000) * 1000 - opts.finishedAgoMs;
	const goMs = finishedMs - HOUR_MS;
	const instanceStart = new Date(goMs).toISOString();
	const eventId = await insertEvent({
		club_id: RICHMOND_RUN_CLUB_ID,
		author_id: USER_A.id,
		title: `e2e-race-retime ${Date.now()}`,
		starts_at: instanceStart
	});
	const seeded: Seeded = { eventId, runId: '', instanceStart };
	opts.onSeeded(seeded);
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
		finished_at: new Date(finishedMs).toISOString(),
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
	seeded.runId = await insertRun({
		user_id: runner.id,
		started_at: new Date(pressMs).toISOString(),
		duration_s: 280,
		distance_m: 1120,
		is_public: opts.runIsPublic ?? false,
		track
	});
	opts.onSeeded(seeded);
	const { error: linkErr } = await admin.from('runs').update({ event_id: eventId }).eq('id', seeded.runId);
	if (linkErr) throw new Error(`run link failed: ${linkErr.message}`);
	if (opts.dnf) {
		const { error: dnfErr } = await admin.from('event_results').insert({
			event_id: eventId,
			instance_start: instanceStart,
			user_id: runner.id,
			course_id: course.id,
			distance_m: 1000,
			duration_s: 0,
			finisher_status: 'dnf',
			finish_method: 'host'
		});
		if (dnfErr) throw new Error(`dnf insert failed: ${dnfErr.message}`);
	}
	return seeded;
}

async function ownRow(eventId: string, runner: SeededUser = USER_A) {
	return readRow(
		'event_results for the re-timed runner',
		getAdminClient()
			.from('event_results')
			.select('finisher_status, finish_method, start_detection, finish_detection, gun_time_s, chip_time_s, run_id')
			.eq('event_id', eventId)
			.eq('user_id', runner.id)
			.single()
	);
}

async function openReadyPanel(page: Page, runId: string) {
	await page.goto(`/runs/${runId}`);
	const panel = page.getByTestId('race-retime');
	await expect(panel).toBeVisible({ timeout: 15_000 });
	await expect(panel.getByTestId('race-retime-state')).toHaveAttribute('data-state', 'ready');
	return panel;
}

async function confirmRetime(page: Page, panel: ReturnType<Page['getByTestId']>) {
	await panel.getByTestId('race-retime-action').click();
	const dialog = page.getByRole('dialog');
	await expect(dialog).toBeVisible({ timeout: 5_000 });
	await dialog.getByRole('button', { name: 'Replace result' }).click();
	await expect(dialog).toBeHidden({ timeout: 10_000 });
}

/** The result write: a call to the filing RPC (decisions § 2474). */
function isResultWrite(url: string, method: string): boolean {
	return new URL(url).pathname.endsWith('/rest/v1/rpc/file_event_result') && method === 'POST';
}

test.describe('/runs/[id] — re-time a race result from the track', () => {
	let eventId: string | null = null;
	let runId: string | null = null;
	const remember = (s: Seeded) => {
		eventId = s.eventId;
		runId = s.runId || null;
	};
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

	test.describe('as the run owner', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('a DNF is replaced by the line-timed result the track gives', async ({ page }) => {
			const s = await seedRace({ finishedAgoMs: HOUR_MS, dnf: true, onSeeded: remember });

			const panel = await openReadyPanel(page, s.runId);
			await expect(panel.getByTestId('race-retime-current-status')).toHaveText('Did not finish');
			await expect(panel.getByTestId('race-retime-new-gun')).toHaveText('4:27');
			await expect(panel.getByTestId('race-retime-new-chip')).toHaveText('4:10');
			await expect(panel.getByTestId('race-retime-new-start')).toHaveText('Start line');
			await expect(panel.getByTestId('race-retime-new-finish')).toHaveText('Finish line');
			await expect(panel.getByTestId('race-retime-clock-device')).toBeVisible();

			await confirmRetime(page, panel);
			await expect(panel.getByTestId('race-retime-state')).toContainText('Result re-timed from your track.', {
				timeout: 10_000
			});
			await expect(panel.getByTestId('race-retime-action')).toHaveCount(0);

			expect(await ownRow(s.eventId)).toMatchObject({
				finisher_status: 'finished',
				finish_method: 'auto',
				start_detection: 'gate',
				finish_detection: 'gate',
				gun_time_s: 267,
				chip_time_s: 250,
				run_id: s.runId
			});
		});

		test('a race that finished more than 24 h ago offers no re-time', async ({ page }) => {
			const s = await seedRace({ finishedAgoMs: 25 * HOUR_MS, dnf: false, onSeeded: remember });

			await page.goto(`/runs/${s.runId}`);
			const panel = page.getByTestId('race-retime');
			await expect(panel).toBeVisible({ timeout: 15_000 });
			const state = panel.getByTestId('race-retime-state');
			await expect(state).toHaveAttribute('data-state', 'closed');
			await expect(state).toHaveText('Results for this race closed 24 hours after it finished.');
			await expect(panel.getByTestId('race-retime-action')).toHaveCount(0);
			await expect(panel.getByTestId('race-retime-compare')).toHaveCount(0);
		});

		test('a failed write is surfaced and leaves the result and the action in place', async ({ page }) => {
			const s = await seedRace({ finishedAgoMs: HOUR_MS, dnf: true, onSeeded: remember });
			await page.route('**/rest/v1/rpc/file_event_result*', (route) =>
				isResultWrite(route.request().url(), route.request().method())
					? route.fulfill({
							status: 500,
							contentType: 'application/json',
							body: JSON.stringify({ code: 'XX000', message: 'e2e write failure' })
						})
					: route.fallback()
			);

			const panel = await openReadyPanel(page, s.runId);
			await confirmRetime(page, panel);
			await expect(page.getByTestId('toast-live-assertive')).toContainText(
				"Couldn't re-time your result. Please try again."
			);
			await expect(panel.getByTestId('race-retime-state')).toHaveAttribute('data-state', 'ready');
			await expect(panel.getByTestId('race-retime-action')).toBeEnabled();
			expect(await ownRow(s.eventId)).toMatchObject({ finisher_status: 'dnf', finish_method: 'host' });
		});

		test('a failed read is surfaced with a retry that loads the panel', async ({ page }) => {
			const s = await seedRace({ finishedAgoMs: HOUR_MS, dnf: true, onSeeded: remember });
			let failReads = true;
			await page.route('**/rest/v1/event_results_redacted*', (route) =>
				failReads
					? route.fulfill({
							status: 500,
							contentType: 'application/json',
							body: JSON.stringify({ code: 'XX000', message: 'e2e read failure' })
						})
					: route.fallback()
			);

			await page.goto(`/runs/${s.runId}`);
			const panel = page.getByTestId('race-retime');
			await expect(panel).toBeVisible({ timeout: 15_000 });
			await expect(panel.getByRole('alert')).toHaveText("Couldn't load this run's race.");
			await expect(panel.getByTestId('race-retime-state')).toHaveCount(0);

			failReads = false;
			await panel.getByRole('button', { name: 'Try again' }).click();
			await expect(panel.getByTestId('race-retime-state')).toHaveAttribute('data-state', 'ready');
			await expect(panel.getByRole('alert')).toHaveCount(0);
		});
	});

	test.describe('as a club member who is not an organiser', () => {
		test.use({ storageState: USER_B.storageStatePath });

		test('the window closing while the panel is open is the server refusal, shown as closed', async ({
			page
		}) => {
			const s = await seedRace({ runner: USER_B, finishedAgoMs: HOUR_MS, dnf: true, onSeeded: remember });
			const panel = await openReadyPanel(page, s.runId);

			// USER_B is a member, not an organiser, so the guard holds them to the
			// window. The race guard measures the window against the session's
			// finished_at at write time; move it past 24 h behind the open panel.
			const { error } = await getAdminClient()
				.from('race_sessions')
				.update({ finished_at: new Date(Date.now() - 25 * HOUR_MS).toISOString() })
				.eq('event_id', s.eventId)
				.eq('instance_start', s.instanceStart);
			if (error) throw new Error(`session move failed: ${error.message}`);

			await confirmRetime(page, panel);
			await expect(panel.getByTestId('race-retime-state')).toHaveAttribute('data-state', 'closed');
			await expect(panel.getByTestId('race-retime-action')).toHaveCount(0);
			expect(await ownRow(s.eventId, USER_B)).toMatchObject({ finisher_status: 'dnf', finish_method: 'host' });
		});
	});

	test.describe('as another runner', () => {
		test.use({ storageState: USER_B.storageStatePath });

		test('a public run linked to a race offers its viewer no re-time and reads nothing for it', async ({
			page
		}) => {
			const s = await seedRace({ finishedAgoMs: HOUR_MS, dnf: true, runIsPublic: true, onSeeded: remember });
			// Only the re-time panel reads the race's frozen course on this page.
			const frozenCourseReads: string[] = [];
			page.on('request', (r) => {
				if (r.url().includes('/rest/v1/race_session_courses')) frozenCourseReads.push(r.url());
			});

			await page.goto(`/runs/${s.runId}`);
			await expect(page.getByTestId('run-detail-skeleton')).toHaveCount(0, { timeout: 15_000 });
			await expect(page.getByTestId('run-load-error')).toHaveCount(0);
			await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
			await expect(page.getByTestId('race-retime')).toHaveCount(0);
			await expect(page.getByRole('heading', { name: 'Re-time from my track' })).toHaveCount(0);
			expect(frozenCourseReads).toEqual([]);
		});
	});
});
