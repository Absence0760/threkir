// The typed edit operations AI plan edits may propose, and the trust boundary
// every one of them passes before it can reach a runner's plan.
//
// The AI is the interface, never the planner (decisions § 12, § 1930, § 1979).
// It turns "move my long run to Sunday" or "make this week easier" into a list
// drawn from five operations, each naming a workout or a week of the runner's
// own plan by a short reference this module hands out. It never emits a
// workout, a distance or a pace: the only numbers it supplies are a calendar
// date (which must fall inside the target workout's own plan week) and a
// scale factor (clamped to a band that cannot add more than 10%). What each
// operation then does to the plan is decided by the deterministic helpers in
// `apply.ts`, and the result is re-graded there before the runner sees it.
//
// Every field the model returns is whitelisted, clamped or dropped here,
// server-side, before the client sees it. A reference that is not one this
// module handed out, an operation on a workout that is already done, skipped,
// in the past or a race, and a second operation on the same target are all
// dropped and counted, never passed through.
//
// Free of the Anthropic SDK and the `$app/env` graph so it is unit-testable in
// isolation (ops.test.ts), and shared by the server handler and the client.

import { shiftIsoDate } from '../plan_bulk_ops';
import { isWorkoutCompleted, isWorkoutSkipped } from '../training';

export const PLAN_EDIT_OP_KINDS = [
	'move_workout',
	'swap_days',
	'scale_week',
	'mark_recovery',
	'skip_workout',
] as const;
export type PlanEditOpKind = (typeof PLAN_EDIT_OP_KINDS)[number];

/// How many operations one request may apply. A request that needs more is
/// not an adjustment, it is a new plan, which is the plan assistant's job.
export const MAX_PLAN_EDIT_OPS = 12;

/// Cap on the runner's change request — the only free text that reaches the
/// prompt besides the plan's own facts. The server truncates past it; the box
/// stops at it.
export const MAX_PLAN_EDIT_REQUEST_CHARS = 400;

/// The scale band. The floor matches the depth of a recovery week and a little
/// beyond; the ceiling lets "a bit more this week" through while a larger
/// step stays impossible to ask for. Anything outside is clamped and named.
export const MIN_SCALE_FACTOR = 0.5;
export const MAX_SCALE_FACTOR = 1.1;

/// How many workouts the model is shown. A 24-week plan at seven days a week
/// is 168; the editable window (today onward) of any plan the wizard builds
/// fits comfortably, and a pasted plan longer than this is cut at the far end,
/// where an adjustment is least likely to be aimed.
export const MAX_PLAN_EDIT_WORKOUTS = 140;

/// Kinds an operation may never touch. A race is the plan's fixed point; a
/// rest day has nothing to move, scale or skip.
const FROZEN_KINDS: ReadonlySet<string> = new Set(['race']);

/// Phases a scale-up may not reach: the taper exists to arrive fresh, the same
/// rule `plan_replan.ts` keeps for its make-ups.
const NO_SCALE_UP_PHASES: ReadonlySet<string> = new Set(['taper', 'race']);

export const PLAN_EDIT_NOTES = ['op_dropped', 'factor_clamped', 'too_many_ops', 'unsupported'] as const;
export type PlanEditNote = (typeof PLAN_EDIT_NOTES)[number];

export interface PlanEditPlan {
	start_date: string;
	end_date: string;
}

export interface PlanEditWeek {
	id: string;
	week_index: number;
	phase: string;
	target_volume_m: number | null;
}

export interface PlanEditWorkout {
	id: string;
	week_id: string;
	scheduled_date: string;
	kind: string;
	target_distance_m: number | null;
	target_duration_seconds?: number | null;
	target_pace_sec_per_km?: number | null;
	target_pace_tolerance_sec?: number | null;
	structure?: unknown;
	completed_run_id?: string | null;
	manually_completed?: boolean | null;
	skipped_at?: string | null;
}

export interface PlanEditSnapshot {
	plan: PlanEditPlan;
	weeks: PlanEditWeek[];
	workouts: PlanEditWorkout[];
}

export type PlanEditOp =
	| { op: 'move_workout'; workoutId: string; date: string }
	| { op: 'swap_days'; workoutId: string; otherWorkoutId: string }
	| { op: 'scale_week'; weekIndex: number; factor: number }
	| { op: 'mark_recovery'; weekIndex: number }
	| { op: 'skip_workout'; workoutId: string };

export interface PlanEditProposal {
	ops: PlanEditOp[];
	/// How many operations the model sent that did not survive validation.
	dropped: number;
	notes: PlanEditNote[];
}

export interface PlanEditContext {
	today: string;
	snapshot: PlanEditSnapshot;
	/// Reference handed to the model -> workout id. Only workouts in weeks that
	/// are not fully past get one, in date order: W1, W2, …
	workoutByRef: Map<string, string>;
	refByWorkout: Map<string, string>;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function epochDay(iso: string): number | null {
	if (!ISO_DATE.test(iso)) return null;
	const [y, m, d] = iso.split('-').map(Number);
	const ms = Date.UTC(y, m - 1, d);
	const back = new Date(ms);
	if (back.getUTCFullYear() !== y || back.getUTCMonth() !== m - 1 || back.getUTCDate() !== d) {
		return null;
	}
	return Math.floor(ms / 86_400_000);
}

/// A plan week's seven days, from the plan's start date. The same arithmetic
/// the plan page uses to date a week (`start_date + week_index * 7`).
export function weekWindow(planStartIso: string, weekIndex: number): { start: string; end: string } {
	const start = shiftIsoDate(planStartIso, weekIndex * 7);
	return { start, end: shiftIsoDate(start, 6) };
}

/// Whether an operation may touch this workout at all: on or after today, not
/// done, not already skipped, and not a race or a rest day.
export function isEditableWorkout(w: PlanEditWorkout, todayIso: string): boolean {
	if (w.scheduled_date < todayIso) return false;
	if (isWorkoutCompleted(w) || isWorkoutSkipped(w)) return false;
	if (FROZEN_KINDS.has(w.kind) || w.kind === 'rest') return false;
	return true;
}

/// A week an operation may reach: it still has a day on or after today.
export function isOpenWeek(plan: PlanEditPlan, week: PlanEditWeek, todayIso: string): boolean {
	return weekWindow(plan.start_date, week.week_index).end >= todayIso;
}

/// Assign the short references the model sees. Sorted by date then id so the
/// same plan always yields the same references.
export function buildPlanEditContext(snapshot: PlanEditSnapshot, todayIso: string): PlanEditContext {
	const openWeekIds = new Set(
		snapshot.weeks.filter((w) => isOpenWeek(snapshot.plan, w, todayIso)).map((w) => w.id),
	);
	const shown = snapshot.workouts
		.filter((w) => openWeekIds.has(w.week_id))
		.sort((a, b) =>
			a.scheduled_date === b.scheduled_date
				? a.id.localeCompare(b.id)
				: a.scheduled_date.localeCompare(b.scheduled_date),
		)
		.slice(0, MAX_PLAN_EDIT_WORKOUTS);
	const workoutByRef = new Map<string, string>();
	const refByWorkout = new Map<string, string>();
	shown.forEach((w, i) => {
		const ref = `W${i + 1}`;
		workoutByRef.set(ref, w.id);
		refByWorkout.set(w.id, ref);
	});
	return { today: todayIso, snapshot, workoutByRef, refByWorkout };
}

function asRef(raw: unknown): string | null {
	return typeof raw === 'string' ? raw.trim().toUpperCase() : null;
}

function finite(raw: unknown): number | null {
	return typeof raw === 'number' && Number.isFinite(raw) ? raw : null;
}

/// Validate the model's raw tool output into operations against the caller's
/// own plan. Never throws: every malformed, unknown, out-of-range or
/// conflicting operation is dropped and counted. This is the single trust
/// boundary between the model and the plan.
export function validatePlanEditOps(raw: unknown, ctx: PlanEditContext): PlanEditProposal {
	const o = (raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {}) as Record<
		string,
		unknown
	>;
	const notes = new Set<PlanEditNote>();
	if (o.unsupported === true) notes.add('unsupported');
	const rawOps = Array.isArray(o.operations) ? o.operations : [];

	const { snapshot, today } = ctx;
	const workoutsById = new Map(snapshot.workouts.map((w) => [w.id, w]));
	const weeksById = new Map(snapshot.weeks.map((w) => [w.id, w]));
	const weeksByIndex = new Map(snapshot.weeks.map((w) => [w.week_index, w]));

	const touchedWorkouts = new Set<string>();
	const touchedWeeks = new Set<number>();
	const ops: PlanEditOp[] = [];
	let dropped = 0;

	const editable = (ref: unknown): PlanEditWorkout | null => {
		const r = asRef(ref);
		const id = r ? ctx.workoutByRef.get(r) : undefined;
		const w = id ? workoutsById.get(id) : undefined;
		if (!w || !isEditableWorkout(w, today) || touchedWorkouts.has(w.id)) return null;
		return w;
	};
	const windowOf = (w: PlanEditWorkout) => {
		const week = weeksById.get(w.week_id);
		return week ? weekWindow(snapshot.plan.start_date, week.week_index) : null;
	};
	const openWeek = (raw: unknown): PlanEditWeek | null => {
		const n = finite(raw);
		if (n === null || !Number.isInteger(n)) return null;
		// The model sees weeks numbered from 1, as the plan page shows them.
		const week = weeksByIndex.get(n - 1);
		if (!week || touchedWeeks.has(week.week_index)) return null;
		const hasEditable = snapshot.workouts.some(
			(w) => w.week_id === week.id && isEditableWorkout(w, today),
		);
		return hasEditable ? week : null;
	};

	for (const item of rawOps) {
		if (ops.length >= MAX_PLAN_EDIT_OPS) {
			notes.add('too_many_ops');
			dropped++;
			continue;
		}
		const op = (item && typeof item === 'object' ? item : {}) as Record<string, unknown>;
		let accepted: PlanEditOp | null = null;
		switch (op.op) {
			case 'move_workout': {
				const w = editable(op.workout);
				const date = typeof op.date === 'string' ? op.date : '';
				const win = w ? windowOf(w) : null;
				if (
					w &&
					win &&
					epochDay(date) !== null &&
					date !== w.scheduled_date &&
					date >= today &&
					date >= win.start &&
					date <= win.end &&
					date <= snapshot.plan.end_date &&
					w.scheduled_date >= win.start &&
					w.scheduled_date <= win.end
				) {
					accepted = { op: 'move_workout', workoutId: w.id, date };
					touchedWorkouts.add(w.id);
				}
				break;
			}
			case 'swap_days': {
				const a = editable(op.workout);
				const b = editable(op.other_workout);
				if (
					a &&
					b &&
					a.id !== b.id &&
					a.week_id === b.week_id &&
					a.scheduled_date !== b.scheduled_date
				) {
					accepted = { op: 'swap_days', workoutId: a.id, otherWorkoutId: b.id };
					touchedWorkouts.add(a.id);
					touchedWorkouts.add(b.id);
				}
				break;
			}
			case 'scale_week': {
				const week = openWeek(op.week);
				const rawFactor = finite(op.factor);
				if (week && rawFactor !== null && rawFactor > 0) {
					const ceiling = NO_SCALE_UP_PHASES.has(week.phase) ? 1 : MAX_SCALE_FACTOR;
					const clamped = Math.min(ceiling, Math.max(MIN_SCALE_FACTOR, rawFactor));
					const factor = Math.round(clamped * 100) / 100;
					if (clamped !== rawFactor) notes.add('factor_clamped');
					if (factor !== 1) {
						accepted = { op: 'scale_week', weekIndex: week.week_index, factor };
						touchedWeeks.add(week.week_index);
					}
				}
				break;
			}
			case 'mark_recovery': {
				const week = openWeek(op.week);
				if (week && week.phase !== 'race') {
					accepted = { op: 'mark_recovery', weekIndex: week.week_index };
					touchedWeeks.add(week.week_index);
				}
				break;
			}
			case 'skip_workout': {
				const w = editable(op.workout);
				if (w) {
					accepted = { op: 'skip_workout', workoutId: w.id };
					touchedWorkouts.add(w.id);
				}
				break;
			}
		}
		if (accepted) ops.push(accepted);
		else {
			dropped++;
			notes.add('op_dropped');
		}
	}

	return { ops, dropped, notes: PLAN_EDIT_NOTES.filter((n) => notes.has(n)) };
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export function isoWeekday(iso: string): string {
	const day = epochDay(iso);
	// 1970-01-01 was a Thursday.
	return day === null ? '' : WEEKDAYS[(((day + 4) % 7) + 7) % 7];
}

function km(m: number | null | undefined): string {
	return m != null && Number.isFinite(m) && m > 0 ? `${(m / 1000).toFixed(1)} km` : '';
}

function minutes(s: number | null | undefined): string {
	return s != null && Number.isFinite(s) && s > 0 ? `${Math.round(s / 60)} min` : '';
}

/// The plan as the model sees it: the open weeks, numbered from 1, with each
/// workout's reference, day, type and size, and whether an operation may touch
/// it. No ids, no notes, no paces and nothing the runner typed into the plan —
/// only what is needed to name a target.
export function describePlanForEdit(ctx: PlanEditContext): string {
	const { snapshot, today } = ctx;
	const lines: string[] = [];
	const weeks = [...snapshot.weeks].sort((a, b) => a.week_index - b.week_index);
	for (const week of weeks) {
		if (!isOpenWeek(snapshot.plan, week, today)) continue;
		const win = weekWindow(snapshot.plan.start_date, week.week_index);
		const items = snapshot.workouts
			.filter((w) => w.week_id === week.id && ctx.refByWorkout.has(w.id))
			.sort((a, b) => (ctx.refByWorkout.get(a.id)! < ctx.refByWorkout.get(b.id)! ? -1 : 1));
		if (items.length === 0) continue;
		const volume = week.target_volume_m ? `, ${km(week.target_volume_m)} planned` : '';
		lines.push(
			`Week ${week.week_index + 1} (${week.phase}, ${isoWeekday(win.start)} ${win.start} to ${isoWeekday(win.end)} ${win.end}${volume})`,
		);
		for (const w of items) {
			const size = [km(w.target_distance_m), minutes(w.target_duration_seconds)]
				.filter(Boolean)
				.join(', ');
			let state = '';
			if (isWorkoutCompleted(w)) state = ' [done]';
			else if (isWorkoutSkipped(w)) state = ' [skipped]';
			else if (w.scheduled_date < today) state = ' [past]';
			else if (!isEditableWorkout(w, today)) state = ' [fixed]';
			lines.push(
				`  ${ctx.refByWorkout.get(w.id)} ${isoWeekday(w.scheduled_date)} ${w.scheduled_date} ${w.kind}${size ? ` ${size}` : ''}${state}`,
			);
		}
	}
	return lines.join('\n');
}
