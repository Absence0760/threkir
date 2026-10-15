import { getAdminClient } from './local-supabase';
import { deleteRoute, deleteRun, insertRoute, insertRun } from './simulate';

/**
 * The least activity an account can have and still have activity: the shape a
 * brand-new account's first minutes leave behind, and the input every derived
 * surface divides by (#1161 round 3). Each row sits at a degenerate edge:
 *
 * - `tinyRun` — 3 m in 10 s, with a 2-point track. A near-zero training load
 *   is what took `/dashboard` down in #1155.
 * - `zeroRun` — 0 m in 10 s, with a single fix, the recorder's output when GPS
 *   never got a second lock. Every pace is a division by zero.
 * - `gymWorkoutId` — one session holding one set of one rep, with no duration.
 * - `routeId` — a 2-point route 10 m long, with no elevation.
 *
 * Instants are relative to now rather than to a calendar day: every surface
 * that buckets them resolves the day in the browser's zone, so read a day back
 * with `browserDateOf(startedAt)` from `dates.ts`.
 *
 * `cleanup()` goes through `deleteRun` so the Storage objects the tracks
 * planted go with their rows (`storage-teardown.test.ts`). It is best-effort
 * and idempotent, and runs before `deleteSagaUsers` wipes the account.
 */
export interface MinimalActivity {
	tinyRun: { id: string; startedAt: string };
	zeroRun: { id: string; startedAt: string };
	gymWorkoutId: string;
	exerciseName: string;
	routeId: string;
	cleanup(): Promise<void>;
}

const LAT = 51.5074;
const LNG = -0.1278;
/** ~3 m of latitude. */
const THREE_METRES_LAT = 0.000027;
/** ~10 m of latitude. */
const TEN_METRES_LAT = 0.00009;

export async function seedMinimalActivity(user: { id: string }): Promise<MinimalActivity> {
	const now = Date.now();
	const tinyStart = new Date(now - 30 * 60_000);
	const zeroStart = new Date(now - 20 * 60_000);
	const gymStart = new Date(now - 10 * 60_000);
	const exerciseName = `Minimal Squat ${now}`;

	const runIds: string[] = [];
	let gymWorkoutId: string | null = null;
	let routeId: string | null = null;

	const cleanup = async () => {
		const admin = getAdminClient();
		for (const id of runIds.splice(0)) {
			await deleteRun(id).catch((e) => console.warn(`seedMinimalActivity cleanup: run ${id}:`, e));
		}
		if (gymWorkoutId) {
			const { error } = await admin.from('gym_workouts').delete().eq('id', gymWorkoutId);
			if (error) console.warn(`seedMinimalActivity cleanup: gym workout ${gymWorkoutId}: ${error.message}`);
			gymWorkoutId = null;
		}
		if (routeId) {
			const id = routeId;
			routeId = null;
			await deleteRoute(id).catch((e) => console.warn(`seedMinimalActivity cleanup: route ${id}:`, e));
		}
	};

	try {
		const tinyRunId = await insertRun({
			user_id: user.id,
			started_at: tinyStart.toISOString(),
			distance_m: 3,
			duration_s: 10,
			source: 'app',
			track: [
				{ lat: LAT, lng: LNG, ele: null, ts: tinyStart.toISOString() },
				{
					lat: LAT + THREE_METRES_LAT,
					lng: LNG,
					ele: null,
					ts: new Date(tinyStart.getTime() + 10_000).toISOString()
				}
			]
		});
		runIds.push(tinyRunId);

		const zeroRunId = await insertRun({
			user_id: user.id,
			started_at: zeroStart.toISOString(),
			distance_m: 0,
			duration_s: 10,
			source: 'app',
			track: [{ lat: LAT, lng: LNG, ele: null, ts: zeroStart.toISOString() }]
		});
		runIds.push(zeroRunId);

		const admin = getAdminClient();
		const { data: workout, error: wErr } = await admin
			.from('gym_workouts')
			.insert({
				user_id: user.id,
				title: 'Minimal session',
				started_at: gymStart.toISOString(),
				last_modified_at: gymStart.toISOString()
			})
			.select('id')
			.single();
		if (wErr || !workout) {
			throw new Error(`seedMinimalActivity: gym_workouts insert failed: ${wErr?.message ?? 'no row'}`);
		}
		gymWorkoutId = workout.id as string;
		const { error: sErr } = await admin.from('gym_sets').insert({
			workout_id: gymWorkoutId,
			set_index: 0,
			exercise_name: exerciseName,
			reps: 1,
			weight_kg: 20
		});
		if (sErr) throw new Error(`seedMinimalActivity: gym_sets insert failed: ${sErr.message}`);

		routeId = await insertRoute({
			user_id: user.id,
			name: 'Minimal route',
			waypoints: [
				{ lat: LAT, lng: LNG },
				{ lat: LAT + TEN_METRES_LAT, lng: LNG }
			],
			distance_m: 10
		});

		return {
			tinyRun: { id: tinyRunId, startedAt: tinyStart.toISOString() },
			zeroRun: { id: zeroRunId, startedAt: zeroStart.toISOString() },
			gymWorkoutId,
			exerciseName,
			routeId,
			cleanup
		};
	} catch (e) {
		await cleanup();
		throw e;
	}
}
