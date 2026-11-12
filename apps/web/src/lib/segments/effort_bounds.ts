/**
 * The client bounds `global_segment_efforts_client_bounds` holds a
 * client-written catalogue effort to (migration 20271225000200), so the web
 * fallback scorer can leave out what the trigger would refuse instead of
 * learning it from a failed write. Keep the constants and rules in step with
 * that trigger.
 *
 * `runs.duration_s` is moving time, so neither rule reads it: an effort may
 * start any time after its run did, and last any length.
 */

export const EFFORT_START_SLACK_S = 60;
export const EFFORT_FOOT_MAX_MPS = 11;
export const EFFORT_CYCLE_MAX_MPS = 25;

export type EffortRefusal = 'starts_before_run' | 'faster_than_activity';

export interface EffortBoundsRun {
	started_at: string;
	activity_type: string;
}

export function globalSegmentEffortRefusal(
	effort: { time_seconds: number; started_at: string },
	run: EffortBoundsRun,
	segmentDistanceM: number | null,
): EffortRefusal | null {
	const effortStart = Date.parse(effort.started_at);
	const runStart = Date.parse(run.started_at);
	if (
		Number.isFinite(effortStart) &&
		Number.isFinite(runStart) &&
		effortStart < runStart - EFFORT_START_SLACK_S * 1000
	) {
		return 'starts_before_run';
	}
	const cap = run.activity_type === 'cycle' ? EFFORT_CYCLE_MAX_MPS : EFFORT_FOOT_MAX_MPS;
	if (segmentDistanceM != null && segmentDistanceM > 0 && segmentDistanceM / effort.time_seconds > cap) {
		return 'faster_than_activity';
	}
	return null;
}

/** Postgres `check_violation`, what the trigger raises. */
const CHECK_VIOLATION = '23514';

export interface EffortWriteResult {
	written: number;
	refused: number;
	/** A failure other than a refusal; the caller should not stamp the run. */
	error: unknown | null;
}

/**
 * Writes the rows in one statement, and when the server refuses that
 * statement for a row (23514), writes them one at a time so a single refused
 * row cannot void the rest. A refusal is permanent for that row, so it is
 * counted rather than reported as an error.
 */
export async function writeEffortsIsolatingRefusals<R>(
	rows: readonly R[],
	write: (batch: R[]) => Promise<{ count: number; error: { code?: string } | null }>,
): Promise<EffortWriteResult> {
	if (rows.length === 0) return { written: 0, refused: 0, error: null };
	const all = await write([...rows]);
	if (!all.error) return { written: all.count, refused: 0, error: null };
	if (all.error.code !== CHECK_VIOLATION) return { written: 0, refused: 0, error: all.error };

	let written = 0;
	let refused = 0;
	let error: unknown | null = null;
	for (const row of rows) {
		const one = await write([row]);
		if (!one.error) written += one.count;
		else if (one.error.code === CHECK_VIOLATION) refused += 1;
		else error ??= one.error;
	}
	return { written, refused, error };
}
