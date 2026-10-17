// Effort and heart-rate targets on a planned workout, and who last edited it
// (issue #1186, decisions § 2092).
//
// `plan_workouts.target_rpe_min/max` (1..10) and `target_hr_min_bpm/max_bpm`
// (30..230) are each a range with either end open: "RPE 3-4" sets both,
// "cap at 125 bpm" sets only the top. The bounds and the ordering rule are the
// columns' CHECKs (migration 20270912000001); this module is the client half
// so a form refuses what the database would.
//
// Twin of `apps/mobile_android/lib/workout_prescription.dart` — keep the
// bounds, the shapes, the rules and the test count in lockstep.

export const RPE_MIN = 1;
export const RPE_MAX = 10;
export const TARGET_HR_MIN_BPM = 30;
export const TARGET_HR_MAX_BPM = 230;

export interface RangeBounds {
	min: number;
	max: number;
}

export const RPE_BOUNDS: RangeBounds = { min: RPE_MIN, max: RPE_MAX };
export const TARGET_HR_BOUNDS: RangeBounds = { min: TARGET_HR_MIN_BPM, max: TARGET_HR_MAX_BPM };

/**
 * How a range reads: `between` (3-4), `exact` (both ends equal), `atMost`
 * (a cap), `atLeast` (a floor). Null when neither end is set.
 */
export type RangeShape = 'between' | 'exact' | 'atMost' | 'atLeast';

export function rangeShape(min: number | null | undefined, max: number | null | undefined): RangeShape | null {
	const lo = min ?? null;
	const hi = max ?? null;
	if (lo == null && hi == null) return null;
	if (lo == null) return 'atMost';
	if (hi == null) return 'atLeast';
	return lo === hi ? 'exact' : 'between';
}

export type ParsedRange =
	| { ok: true; min: number | null; max: number | null }
	| { ok: false; reason: 'notWhole' | 'outOfRange' | 'reversed' };

/**
 * Validate a typed range. Each end may be empty (null). An end must be a whole
 * number inside [bounds], and a low end may not exceed the high end.
 */
export function parseTargetRange(
	min: number | null | undefined,
	max: number | null | undefined,
	bounds: RangeBounds
): ParsedRange {
	const lo = min ?? null;
	const hi = max ?? null;
	for (const v of [lo, hi]) {
		if (v == null) continue;
		if (!Number.isFinite(v) || !Number.isInteger(v)) return { ok: false, reason: 'notWhole' };
		if (v < bounds.min || v > bounds.max) return { ok: false, reason: 'outOfRange' };
	}
	if (lo != null && hi != null && lo > hi) return { ok: false, reason: 'reversed' };
	return { ok: true, min: lo, max: hi };
}

/**
 * True when someone other than the plan's owner made the workout's last edit,
 * seen by the owner. Only the owner and an active coach can write a plan's
 * workouts (RLS, 20261116_001), so for the owner a different editor is their
 * coach. Null `updated_by` (never edited, or a server-side write) is not.
 */
export function isEditedByCoach(
	workout: { updated_by?: string | null },
	ownerId: string | null | undefined,
	viewerId: string | null | undefined
): boolean {
	if (!ownerId || !viewerId || viewerId !== ownerId) return false;
	const editor = workout.updated_by ?? null;
	return editor != null && editor !== ownerId;
}
