/**
 * Anchor the weeks ahead to what the runner actually ran (issue #1186,
 * "a niggle week gets no real response").
 *
 * `replanRemaining` reacts to a missed long run and to over-running, but a
 * week that came in well short changes nothing ahead of it: the plan carries
 * on up its nominal ramp, so the week after a niggle asks for more than the
 * week the runner could not finish. A coach answers that week by building
 * back from what was run, at about 10% a week, until the plan's own weeks
 * fit again. That is this module.
 *
 * Distance only: it reads planned and actual weekly volume and nothing
 * derived from heart rate or training load. It still ships behind
 * `ADAPTIVE_FITNESS_GATE` (decisions § 2090, § 144 / § 150), because it
 * rewrites the weeks ahead from what was run, which is the second-wave
 * prescription work that sign-off covers. The gate is the caller's: Home and
 * the plan page call this only while it is on.
 *
 * The rules:
 *  - It speaks when the last completed week ran under plan (`weeklyDrift`'s
 *    20% band, against the smaller of the week's target and what its
 *    sessions prescribe, so a week already anchored and run as prescribed is
 *    not short), or when the runner has been away from the plan for
 *    `LAYOFF_MIN_DAYS` or more: a resumed or rescheduled plan whose skipped
 *    weeks are a layoff, whether or not the week before it was on target.
 *  - The anchor is the most recent completed week with any running in it. A
 *    week with none is a break, not a level, and a plan with no such week has
 *    no evidence of the runner's level, so it proposes nothing.
 *  - The first week ahead may ask for at most 10% over the anchor; after a
 *    layoff, at most `RETURN_WEEK_SHARE` of it, the wizard's returning-runner
 *    opening (decisions § 2090). Each later week may ask for at most 10% over
 *    the most any week since prescribes, so a step-back week holds the climb.
 *  - Only future, undone, unskipped, distance-targeted sessions shrink, all by
 *    one factor so the week keeps its shape, down to the 100 m. None goes
 *    below the generator's 3 km easy floor, and one already at or under it is
 *    left alone. Done sessions count toward their week as prescribed; missed
 *    ones count nothing. Rest and race sessions are never counted or touched.
 *  - The climb stops at the first taper or race week. The taper is sacred,
 *    exactly as in `replanRemaining`.
 *
 * It returns proposals in the re-plan engine's own `ReplanChange` shape, so
 * they go through the same preview and the same `apply_workout_adjustments`
 * write as every other re-plan.
 *
 * Mirrors `apps/mobile_android/lib/plan_volume_anchor.dart` — keep in lockstep
 * (TS↔Dart parity pair, equal test counts).
 */

import { weeklyDrift } from './plan_adherence';
import { LAYOFF_MIN_DAYS, RETURN_WEEK_SHARE, RETURN_WEEKLY_GROWTH } from './comeback';
import { EASY_RUN_FLOOR_KM } from './training';
import type { ReplanChange, ReplanWeek, ReplanWorkout } from './plan_replan';

const TAPER_PHASES = new Set(['taper', 'race']);
const FLOOR_M = EASY_RUN_FLOOR_KM * 1000;

export interface VolumeAnchor {
	changes: ReplanChange[];
	/// The completed week whose running the climb starts from.
	anchorWeekIndex: number;
	/// What the runner ran in that week, metres.
	anchorMetres: number;
	/// Plan weeks between the anchor week and the weeks ahead: completed weeks
	/// with no running, plus weeks a resume skipped over.
	idleWeeks: number;
	/// The idle stretch is a layoff, so the climb restarts from
	/// `RETURN_WEEK_SHARE` of the anchor rather than from the anchor itself.
	returning: boolean;
}

function isFixed(kind: string): boolean {
	return kind === 'rest' || kind === 'race';
}

/// What a completed week asked for: its target, or less when its sessions
/// add up to less (the anchor lowers sessions, never the week's target).
function prescribedMetres(week: ReplanWeek): number {
	let sessions = 0;
	for (const wo of week.workouts) {
		if (wo.kind !== 'rest') sessions += wo.targetDistanceM ?? 0;
	}
	return sessions > 0 ? Math.min(week.plannedMetres, sessions) : week.plannedMetres;
}

/// The proposal, or null when nothing ahead needs to change.
export function anchorToActualVolume(input: { weeks: ReplanWeek[] }): VolumeAnchor | null {
	const weeks = [...input.weeks].sort((a, b) => a.weekIndex - b.weekIndex);
	const completed = weeks.filter((w) => w.isComplete);
	const lastComplete = completed.at(-1);
	if (!lastComplete) return null;
	const ahead = weeks.filter((w) => w.weekIndex > lastComplete.weekIndex);
	if (ahead.length === 0) return null;
	const anchor = [...completed].reverse().find((w) => w.actualMetres > 0);
	if (!anchor) return null;

	const idleWeeks = ahead[0].weekIndex - anchor.weekIndex - 1;
	const returning = idleWeeks * 7 >= LAYOFF_MIN_DAYS;
	const under =
		weeklyDrift(prescribedMetres(lastComplete), lastComplete.actualMetres).direction === 'under';
	if (!under && !returning) return null;

	const changes: ReplanChange[] = [];
	// The level the climb resumes from: what was run, or the return share of
	// it after a layoff, which is itself the first week's cap. Every cap after
	// grows from the most any week since prescribes, so an empty or step-back
	// week ahead holds the climb rather than lowering it.
	let highest = returning ? anchor.actualMetres * RETURN_WEEK_SHARE : anchor.actualMetres;
	let cap = returning ? highest : highest * RETURN_WEEKLY_GROWTH;
	for (const week of ahead) {
		if (TAPER_PHASES.has(week.phase)) break;

		let fixed = 0;
		let adjustableM = 0;
		const adjustable: ReplanWorkout[] = [];
		for (const wo of week.workouts) {
			if (isFixed(wo.kind) || wo.skipped) continue;
			const target = wo.targetDistanceM ?? 0;
			if (!(target > 0)) continue;
			if (wo.completed) fixed += target;
			else if (wo.isPast) continue;
			else {
				adjustable.push(wo);
				adjustableM += target;
			}
		}

		let prescribed = fixed + adjustableM;
		if (prescribed > cap && adjustableM > 0) {
			const factor = Math.max(0, cap - fixed) / adjustableM;
			prescribed = fixed;
			for (const wo of adjustable) {
				const target = wo.targetDistanceM as number;
				const next =
					target <= FLOOR_M ? target : Math.max(FLOOR_M, Math.floor((target * factor) / 100) * 100);
				prescribed += next;
				if (next < target) {
					changes.push({
						workoutId: wo.id,
						scheduledDate: wo.scheduledDate,
						reason: 'anchor_actual_volume',
						field: 'target_distance_m',
						fromMetres: target,
						toMetres: next,
					});
				}
			}
		}
		highest = Math.max(highest, prescribed);
		cap = highest * RETURN_WEEKLY_GROWTH;
	}

	if (changes.length === 0) return null;
	return {
		changes,
		anchorWeekIndex: anchor.weekIndex,
		anchorMetres: anchor.actualMetres,
		idleWeeks,
		returning,
	};
}

/// An under-run week is answered by the anchor alone. A make-up stretch or
/// any other proposal beside it would push the capped weeks back up, so when
/// the anchor has something to say, nothing else is proposed with it.
export function preferVolumeAnchor(
	anchor: VolumeAnchor | null,
	otherwise: ReplanChange[],
): ReplanChange[] {
	return anchor ? anchor.changes : otherwise;
}
