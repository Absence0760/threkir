// The scope of an AI plan edit once plans chain (issue #1213, decisions § 2230).
//
// A runner with blocks queued behind the plan they are editing chooses where an
// intensity or volume change lands: this block only (the default), or this block
// and every active block chained after it. Only a uniform scale carries
// forward — move, swap and skip name individual workouts, and a recovery week
// is one week — so the choice is offered only when the validated operations
// scale weeks in one direction. The following blocks get that factor on every
// open week, through `validatePlanEditOps` (so the 0.5-1.1 clamp and the
// taper/race-week cap of 1.0 are the same rule) and `applyPlanEditOps` (so the
// B/C race windows stay unscaled on a scale-up), then each block is graded on
// its own with `planEditLoadCheck` and the worst verdict decides.
//
// A plan that is completed or already over is never part of a season edit
// (§ 2052): the caller passes only active plans, and `apply_ai_plan_edits`
// re-checks it.
//
// Pure: no Supabase, no DOM.

import {
	applyPlanEditOps,
	blockRaces,
	planEditLoadCheck,
	plannedWeekVolumeM,
	PLAN_EDIT_CHRONIC_WEEKS,
	type PlanEditApplication,
	type PlanEditLoadCheck,
	type PlanEditLoadVerdict,
	type WorkoutPatch,
} from './apply';
import {
	MAX_PLAN_EDIT_OPS,
	buildPlanEditContext,
	validatePlanEditOps,
	type PlanEditOp,
	type PlanEditSnapshot,
} from './ops';
import { MIN_ACTIVE_WEEKS, type RecentVolume } from '../plan_ramp';
import type { PlanRace } from '../plan_races';
import type { PlanWeek, PlanWorkout, TrainingPlan } from '../../types';

export type PlanEditScope = 'plan' | 'season';

export interface PlanEditBlock {
	planId: string;
	name: string;
	snapshot: PlanEditSnapshot;
}

export interface BlockEdit {
	planId: string;
	name: string;
	application: PlanEditApplication;
	check: PlanEditLoadCheck;
}

export interface SeasonEdit {
	scope: PlanEditScope;
	/// The edited plan first, then each following block the edit changes.
	blocks: BlockEdit[];
	verdict: PlanEditLoadVerdict;
}

type Recent = Pick<RecentVolume, 'weeklyM' | 'activeWeeks'>;

/// The factor "and the following blocks" carries forward, or null when the
/// edit has nothing to carry: no scale_week at all, or scales that disagree
/// on direction. Several scales in one direction carry the one closest to
/// 1.0, the mildest change the runner was shown.
export function cascadeFactor(ops: readonly PlanEditOp[]): number | null {
	const factors = ops.flatMap((o) => (o.op === 'scale_week' ? [o.factor] : []));
	if (factors.length === 0) return null;
	if (factors.every((f) => f < 1)) return Math.max(...factors);
	if (factors.every((f) => f > 1)) return Math.min(...factors);
	return null;
}

/// One scale_week per open week of a following block, validated against that
/// block exactly as the model's own operations are. Weeks are validated in
/// batches of `MAX_PLAN_EDIT_OPS`, since a block can be longer than one
/// request's operation cap; each week still appears once.
export function cascadeOps(block: PlanEditSnapshot, factor: number, todayIso: string): PlanEditOp[] {
	const ctx = buildPlanEditContext(block, todayIso);
	const weeks = [...block.weeks].sort((a, b) => a.week_index - b.week_index);
	const ops: PlanEditOp[] = [];
	for (let i = 0; i < weeks.length; i += MAX_PLAN_EDIT_OPS) {
		const operations = weeks
			.slice(i, i + MAX_PLAN_EDIT_OPS)
			.map((w) => ({ op: 'scale_week', week: w.week_index + 1, factor }));
		ops.push(...validatePlanEditOps({ operations }, ctx).ops);
	}
	return ops;
}

/// What a following block's first weeks are graded against: the mean planned
/// volume of the last (up to four) weeks of the block before it, as it stood
/// before the edit. That block's planned load is the load the runner arrives
/// with; their recent runs describe a date months earlier. Holding the base at
/// the unedited value grades a scale-up at least as strictly as the edited
/// tail would. A gap between the blocks is not counted as zero weeks: what the
/// runner does in it is unplanned, not nothing, and zeros would put the
/// block's first weeks in the high band before any edit, so no edit could
/// ever be blamed for raising them (decisions § 2230).
export function chainedBase(previous: PlanEditSnapshot): Recent {
	const tail = [...previous.weeks]
		.sort((a, b) => a.week_index - b.week_index)
		.slice(-PLAN_EDIT_CHRONIC_WEEKS);
	const volumes = tail.map((w) => plannedWeekVolumeM(previous, w.id));
	const mean = volumes.length > 0 ? volumes.reduce((s, v) => s + v, 0) / volumes.length : 0;
	return { weeklyM: mean, activeWeeks: mean > 0 ? MIN_ACTIVE_WEEKS : 0 };
}

/// Every race of every block in the edit, and of the block just before it: a
/// B race at the end of one block has a recovery window reaching into the
/// next (including a block that ended yesterday, into today), and one at the
/// start of a block a taper reaching back into the one before.
/// `apply_ai_plan_edits` re-checks the windows of the same plans: the edit's
/// own and the preceding one (`fetchPrecedingPlan`). In 'plan' scope the
/// client also counts the following blocks' races, which only ever holds
/// more workouts back than the server requires.
export function seasonRaces(
	primary: PlanEditBlock,
	following: readonly PlanEditBlock[],
	preceding: PlanEditBlock | null = null,
): PlanRace[] {
	return [...(preceding ? [preceding] : []), primary, ...following].flatMap((b) =>
		blockRaces(b.snapshot),
	);
}

/// A plan as read by `fetchPlan`, as the block an AI plan edit works on.
export function planEditBlock(
	plan: Pick<TrainingPlan, 'id' | 'name' | 'start_date' | 'end_date' | 'goal_distance_m' | 'goal_time_seconds'>,
	weeks: readonly Pick<PlanWeek, 'id' | 'week_index' | 'phase' | 'target_volume_m'>[],
	workouts: readonly PlanWorkout[],
): PlanEditBlock {
	return {
		planId: plan.id,
		name: plan.name,
		snapshot: {
			plan: {
				start_date: plan.start_date,
				end_date: plan.end_date,
				goal_distance_m: plan.goal_distance_m,
				goal_time_seconds: plan.goal_time_seconds,
			},
			weeks: weeks.map((w) => ({
				id: w.id,
				week_index: w.week_index,
				phase: w.phase,
				target_volume_m: w.target_volume_m,
			})),
			workouts: workouts.map((w) => ({ ...w })),
		},
	};
}

const VERDICT_RANK: Record<PlanEditLoadVerdict, number> = { ok: 0, confirm: 1, reject: 2 };

/// Apply the validated operations to the edited plan and, with scope
/// 'season', carry a uniform scale into each following block (in date
/// order), grading every changed block. A following block the carried scale
/// leaves unchanged (all of it taper, say) is not listed.
export function planSeasonEdit(input: {
	primary: PlanEditBlock;
	ops: PlanEditOp[];
	following: readonly PlanEditBlock[];
	/// The block before the plan, for its race windows only; never edited.
	preceding?: PlanEditBlock | null;
	recent: Recent;
	todayIso: string;
	scope: PlanEditScope;
}): SeasonEdit {
	const { primary, ops, following, recent, todayIso, scope } = input;
	const races = seasonRaces(primary, following, input.preceding ?? null);
	const first = applyPlanEditOps(primary.snapshot, ops, todayIso, races);
	const blocks: BlockEdit[] = [
		{
			planId: primary.planId,
			name: primary.name,
			application: first,
			check: planEditLoadCheck(primary.snapshot, first.after, recent, todayIso),
		},
	];
	const factor = scope === 'season' ? cascadeFactor(ops) : null;
	if (factor != null) {
		let previous = primary.snapshot;
		for (const block of following) {
			const application = applyPlanEditOps(
				block.snapshot,
				cascadeOps(block.snapshot, factor, todayIso),
				todayIso,
				races,
			);
			if (application.workouts.length > 0 || application.weeks.length > 0) {
				blocks.push({
					planId: block.planId,
					name: block.name,
					application,
					check: planEditLoadCheck(block.snapshot, application.after, chainedBase(previous), todayIso),
				});
			}
			previous = block.snapshot;
		}
	}
	let verdict: PlanEditLoadVerdict = 'ok';
	for (const b of blocks) {
		if (VERDICT_RANK[b.check.verdict] > VERDICT_RANK[verdict]) verdict = b.check.verdict;
	}
	return { scope, blocks, verdict };
}

/// Whether the scope choice applies: the edit carries a uniform scale and at
/// least one following block would change under it.
export function offersSeasonScope(
	primary: PlanEditBlock,
	ops: readonly PlanEditOp[],
	following: readonly PlanEditBlock[],
	todayIso: string,
	preceding: PlanEditBlock | null = null,
): boolean {
	const factor = cascadeFactor(ops);
	if (factor == null) return false;
	const races = seasonRaces(primary, following, preceding);
	return following.some((b) => {
		const app = applyPlanEditOps(b.snapshot, cascadeOps(b.snapshot, factor, todayIso), todayIso, races);
		return app.workouts.length > 0 || app.weeks.length > 0;
	});
}

export type AiPlanEditWorkoutChange = { id: string } & WorkoutPatch & { skip?: true };

export interface AiPlanEditPayload {
	workouts: AiPlanEditWorkoutChange[];
	weeks: { id: string; target_volume_m: number }[];
}

/// The `apply_ai_plan_edits` arguments for an edit: every changed workout's
/// patch (plus `skip`) and every changed week target, across all its blocks.
/// The RPC re-checks each one against the rows as they are.
export function aiPlanEditPayload(edit: SeasonEdit): AiPlanEditPayload {
	const workouts: AiPlanEditWorkoutChange[] = [];
	const weeks: AiPlanEditPayload['weeks'] = [];
	for (const block of edit.blocks) {
		for (const c of block.application.workouts) {
			workouts.push({ id: c.workoutId, ...(c.patch ?? {}), ...(c.skip ? { skip: true as const } : {}) });
		}
		for (const w of block.application.weeks) {
			if (w.afterVolumeM != null) weeks.push({ id: w.weekId, target_volume_m: w.afterVolumeM });
		}
	}
	return { workouts, weeks };
}
