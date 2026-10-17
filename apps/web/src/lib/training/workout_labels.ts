import { m } from '#lib/i18n/store.svelte.ts';
import type { MessageKey } from '#lib/i18n/messages.ts';
import type { WorkoutKind, PlanPhase } from './training';

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
