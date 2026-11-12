// The Today card's "ask once" about a missed workout (decisions § 2122). Pure:
// which miss to ask about, what the engine advises for it, and the make-up the
// runner previews when the advice is to make it up. It adds no rule of its
// own: "missed" is plan_current's `isWorkoutMissed`, the advice is
// plan_adherence's `missedWorkoutAdvice`, and the make-up is plan_replan's
// stretched next long run. Dart twin `apps/mobile_android/lib/plan_missed_prompt.dart`.

import { missedWorkoutAdvice, type MissedWorkoutAdvice } from './plan_adherence';
import { isWorkoutMissed } from './plan_current';
import {
	recoveryWeekImminent,
	replanRemaining,
	type ReplanChange,
	type ReplanWeek
} from './plan_replan';

/// Only a miss from the last week is asked about. An older one has already
/// slipped past the week it belonged to, and asking about it would read as a
/// reproach rather than a decision still worth making.
export const MISSED_PROMPT_WINDOW_DAYS = 7;

const TAPER_PHASES = new Set(['taper', 'race']);

export interface MissedPromptWorkout {
	id: string;
	/// ISO scheduled date (YYYY-MM-DD).
	scheduledDate: string;
	kind: string;
	targetDistanceM: number | null;
	completed: boolean;
	skipped: boolean;
	/// The runner already answered the prompt for this workout
	/// (`plan_workouts.missed_ack_at`).
	answered: boolean;
}

export interface MissedPromptWeek {
	weekIndex: number;
	phase: string;
	plannedMetres: number;
	workouts: MissedPromptWorkout[];
}

export interface MissedPrompt {
	workoutId: string;
	scheduledDate: string;
	kind: string;
	advice: MissedWorkoutAdvice;
	/// The stretched next long run the runner previews. Null when the advice
	/// is to let it go, or when no later long run is short of the miss.
	makeUp: ReplanChange | null;
	/// Every unanswered missed long run the make-up honours. They are answered
	/// together with it, so none of them is asked about, or made up, again.
	makeUpAnswers: string[];
}

function isoMinusDays(iso: string, days: number): string {
	const d = new Date(`${iso}T00:00:00Z`);
	d.setUTCDate(d.getUTCDate() - days);
	return d.toISOString().slice(0, 10);
}

function missed(wo: MissedPromptWorkout, today: string): boolean {
	return isWorkoutMissed(
		{ scheduled_date: wo.scheduledDate, kind: wo.kind, completed: wo.completed, skipped: wo.skipped },
		today
	);
}

/// The most recent unanswered miss from the last `windowDays` days, or null.
/// Two misses on one day keep the earlier in plan order.
export function missedWorkoutPrompt(input: {
	weeks: MissedPromptWeek[];
	/// The runner's local today (YYYY-MM-DD).
	today: string;
	windowDays?: number;
}): MissedPrompt | null {
	const { today } = input;
	const windowStart = isoMinusDays(today, input.windowDays ?? MISSED_PROMPT_WINDOW_DAYS);
	const weeks = [...input.weeks].sort((a, b) => a.weekIndex - b.weekIndex);
	const replanWeeks: ReplanWeek[] = weeks.map((w) => ({
		weekIndex: w.weekIndex,
		phase: w.phase,
		plannedMetres: w.plannedMetres,
		actualMetres: 0,
		isComplete: false,
		workouts: []
	}));

	let pick: { wo: MissedPromptWorkout; idx: number } | null = null;
	for (let i = 0; i < weeks.length; i++) {
		for (const wo of weeks[i].workouts) {
			if (wo.answered || wo.scheduledDate < windowStart || !missed(wo, today)) continue;
			if (pick === null || wo.scheduledDate > pick.wo.scheduledDate) pick = { wo, idx: i };
		}
	}
	if (pick === null) return null;

	const adviceFor = (kind: string, idx: number) =>
		missedWorkoutAdvice({
			kind,
			isTaper: TAPER_PHASES.has(weeks[idx].phase),
			recoveryWeekImminent: recoveryWeekImminent(replanWeeks, idx)
		});
	const advice = adviceFor(pick.wo.kind, pick.idx);
	const result: MissedPrompt = {
		workoutId: pick.wo.id,
		scheduledDate: pick.wo.scheduledDate,
		kind: pick.wo.kind,
		advice,
		makeUp: null,
		makeUpAnswers: []
	};
	if (advice.recommendation !== 'make_up') return result;

	// An answered miss is off the books for the make-up, as a skipped one is:
	// the runner already let it go, or already made it up.
	const { changes } = replanRemaining({
		weeks: weeks.map((w, i) => ({
			...replanWeeks[i],
			workouts: w.workouts.map((wo) => ({
				id: wo.id,
				scheduledDate: wo.scheduledDate,
				kind: wo.kind,
				targetDistanceM: wo.targetDistanceM,
				completed: wo.completed,
				skipped: wo.skipped || wo.answered,
				isPast: wo.scheduledDate < today
			}))
		})),
		today
	});
	const makeUp = changes.find((c) => c.reason === 'make_up_long') ?? null;
	if (makeUp === null) return result;

	const answers: string[] = [];
	for (let i = 0; i < weeks.length; i++) {
		for (const wo of weeks[i].workouts) {
			if (wo.kind !== 'long' || wo.answered || !missed(wo, today)) continue;
			if (adviceFor('long', i).recommendation === 'make_up') answers.push(wo.id);
		}
	}
	return { ...result, makeUp, makeUpAnswers: answers };
}
