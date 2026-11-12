import { m } from '#lib/i18n/store.svelte.ts';
import type { MessageKey } from '#lib/i18n/messages.ts';
import type { WorkoutKind, PlanPhase } from './training';
import {
	weekAdviceKind,
	type AdviceWeekWorkout,
	type WeekAdviceKind,
	type WorkoutAdviceKind
} from './plan_advice.ts';

// Presentation-layer labels for the training enums. They live here rather
// than in training.ts so that module stays a pure, locale-free twin of
// training.dart; the localized strings are catalogue keys resolved through
// m(). Reading m() inside the call (a component template / $derived) keeps
// the label reactive to locale changes.

const WORKOUT_KIND_KEY: Record<WorkoutKind, MessageKey> = {
	easy: 'workoutKind.easy',
	long: 'workoutKind.long',
	recovery: 'workoutKind.recovery',
	tempo: 'workoutKind.tempo',
	interval: 'workoutKind.interval',
	marathon_pace: 'workoutKind.marathon_pace',
	walk_run: 'workoutKind.walk_run',
	race: 'workoutKind.race',
	rest: 'workoutKind.rest',
};

// The compact form a 7-column grid cell can hold below ~600 px, where the
// full word is cut to an ellipsis and the 3 px colour edge (six marks for nine
// kinds) was left to name the kind. The full label stays in the cell's
// accessible name.
const WORKOUT_KIND_SHORT_KEY: Record<WorkoutKind, MessageKey> = {
	easy: 'workoutKindShort.easy',
	long: 'workoutKindShort.long',
	recovery: 'workoutKindShort.recovery',
	tempo: 'workoutKindShort.tempo',
	interval: 'workoutKindShort.interval',
	marathon_pace: 'workoutKindShort.marathon_pace',
	walk_run: 'workoutKindShort.walk_run',
	race: 'workoutKindShort.race',
	rest: 'workoutKindShort.rest',
};

const PLAN_PHASE_KEY: Record<PlanPhase, MessageKey> = {
	base: 'planPhase.base',
	build: 'planPhase.build',
	peak: 'planPhase.peak',
	taper: 'planPhase.taper',
	race: 'planPhase.race',
	graduation: 'planPhase.graduation',
};

export function workoutKindLabel(kind: string): string {
	const key = WORKOUT_KIND_KEY[kind as WorkoutKind];
	return key ? m(key) : kind;
}

export function workoutKindShortLabel(kind: string): string {
	const key = WORKOUT_KIND_SHORT_KEY[kind as WorkoutKind];
	return key ? m(key) : kind;
}

export function planPhaseLabel(phase: string): string {
	const key = PLAN_PHASE_KEY[phase as PlanPhase];
	return key ? m(key) : phase;
}

const WEEK_ADVICE_KEY: Record<WeekAdviceKind, MessageKey> = {
	race: 'planDetail.weekAdvice.race',
	taper: 'planDetail.weekAdvice.taper',
	graduation: 'planDetail.weekAdvice.graduation',
	walk_breaks: 'planDetail.weekAdvice.walkBreaks',
	back_to_back: 'planDetail.weekAdvice.backToBack',
};

/// The note a week shows: the runner's or coach's own when the row holds one,
/// else the advice its phase and workouts carry (plan_advice.ts).
export function planWeekNote(
	notes: string | null | undefined,
	phase: string,
	workouts: readonly AdviceWeekWorkout[]
): string | null {
	if (notes) return notes;
	const kind = weekAdviceKind(phase, workouts);
	return kind ? m(WEEK_ADVICE_KEY[kind]) : null;
}

export const WORKOUT_ADVICE_KEY: Record<WorkoutAdviceKind, MessageKey> = {
	easy: 'workoutDetail.adviceEasy',
	long: 'workoutDetail.adviceLong',
	time_on_feet: 'workoutDetail.adviceTimeOnFeet',
	tempo: 'workoutDetail.adviceTempo',
	interval: 'workoutDetail.adviceInterval',
	marathon_pace: 'workoutDetail.adviceMarathonPace',
	walk_run: 'workoutDetail.adviceWalkRun',
	race: 'workoutDetail.adviceRace',
	ultra_race: 'workoutDetail.adviceUltraRace',
	rest: 'workoutDetail.adviceRest',
};
