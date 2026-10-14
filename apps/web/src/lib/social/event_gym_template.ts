/**
 * The class -> gym seam: a typed contract over the loose `events.gym_template`
 * jsonb bag (migration 20261227_001 + the SELECT grant in 20261230_001).
 *
 * `gym_template` is meaningful only for `category === 'class'`. A host attaches
 * an optional discipline + default duration; an attendee one-tap-logs the class
 * as a gym workout, pre-filled from this template (they confirm in the composer
 * — inform-tier, nothing auto-writes).
 *
 * Dart twin: `apps/mobile_android/lib/event_gym_template.dart` — keep in
 * lockstep (same parse tolerance, same build rules, same draft shape).
 */

import { namesAnExercise } from '../gym/gym_prs';
import { prefillFromRoutine, type PlannedRoutine } from '../gym/gym_routine';
import type { SessionStep } from './session_steps';

/**
 * An alias rather than an interface, and that is load-bearing: only an alias
 * of an object type gets TypeScript's implicit index signature, so an
 * interface is refused as the `Json` this jsonb column takes however
 * JSON-shaped it is. The Dart twin has no such distinction.
 */
export type EventGymTemplate = {
	discipline: string | null;
	duration_min: number | null;
};

/** The minimal GymEditor seed the seam produces from a template. */
export interface GymWorkoutDraft {
	title: string | null;
	duration_s: number | null;
}

function asString(v: unknown): string | null {
	if (typeof v !== 'string') return null;
	const t = v.trim();
	return t === '' ? null : t;
}

function asPositiveInt(v: unknown): number | null {
	if (typeof v !== 'number' || !Number.isFinite(v)) return null;
	const n = Math.floor(v);
	return n > 0 ? n : null;
}

/**
 * Parse the raw jsonb into a typed template, tolerant of the loose bag.
 * Returns `null` when the value is absent, malformed, or carries neither a
 * discipline nor a duration (an effectively-empty template), so callers can
 * treat "no template" and "empty template" identically.
 */
export function parseGymTemplate(json: unknown): EventGymTemplate | null {
	if (json == null || typeof json !== 'object' || Array.isArray(json)) return null;
	const bag = json as Record<string, unknown>;
	const discipline = asString(bag.discipline);
	const duration_min = asPositiveInt(bag.duration_min);
	if (discipline === null && duration_min === null) return null;
	return { discipline, duration_min };
}

/**
 * Build the template to persist from the editor inputs. Returns `null` when
 * both are empty so a class without a template writes NULL (not `{}`), which
 * keeps the attendee affordance hidden for an un-templated class.
 */
export function gymTemplateFromInputs(
	discipline: string | null | undefined,
	durationMin: number | null | undefined
): EventGymTemplate | null {
	const d = asString(discipline ?? null);
	const m = asPositiveInt(durationMin ?? null);
	if (d === null && m === null) return null;
	return { discipline: d, duration_min: m };
}

/**
 * Produce the GymEditor prefill from a template. The title falls back to the
 * event title when the class carries no discipline; sets stay empty for the
 * user to fill in the composer.
 */
export function workoutDraftFromTemplate(
	template: EventGymTemplate | null,
	eventTitle: string | null | undefined
): GymWorkoutDraft {
	const title = template?.discipline ?? asString(eventTitle ?? null);
	const min = template?.duration_min ?? null;
	return {
		title,
		duration_s: min === null ? null : min * 60
	};
}

/** One logged set per expanded session step (the class -> gym log seam, M5). */
export interface SessionDraftItem {
	exercise_name: string;
	duration_s: number | null;
	reps: number | null;
}

/**
 * Produce the gym-log prefill from an expanded session plan (M5 follow-along
 * log). The title prefers the class discipline, falling back to the plan title;
 * the duration is the plan's total estimate. Each expanded step becomes one set
 * (a per-side step stays two rows) — the side word is never baked into the
 * exercise name, callers localize it.
 */
export function workoutDraftFromSession(
	expanded: { steps: SessionStep[]; totalS: number },
	planTitle: string | null | undefined,
	discipline: string | null | undefined
): GymWorkoutDraft & { sets: SessionDraftItem[] } {
	const title = asString(discipline ?? null) ?? asString(planTitle ?? null);
	return {
		title,
		duration_s: expanded.totalS > 0 ? expanded.totalS : null,
		sets: expanded.steps.map((step) => ({
			exercise_name: step.movementName,
			duration_s: step.durationS,
			reps: step.reps
		}))
	};
}

/** One logged set per planned routine set (the class -> gym log seam). */
export interface RoutineDraftItem {
	exercise_name: string;
	reps: number | null;
	weight_kg: number | null;
	rpe: number | null;
}

function wholeOrNull(input: string): number | null {
	if (input === '') return null;
	const n = Number(input);
	return Number.isInteger(n) ? n : null;
}

function finiteOrNull(input: string): number | null {
	if (input === '') return null;
	const n = Number(input);
	return Number.isFinite(n) ? n : null;
}

/**
 * Produce the gym-log prefill from a class's attached gym routine. The routine
 * is the club's template and stays theirs: this only seeds the attendee's own
 * new workout (decisions § 1869). Goes through `prefillFromRoutine`, so the
 * order and target-to-field mapping are exactly the "Start routine" ones: one
 * set per planned set, its reps from the target minimum (a fractional target
 * reads as no reps), weight from the target load, RPE from the target RPE. An
 * exercise with no planned sets keeps one blank row; a blank-named exercise is
 * dropped. The title prefers the class discipline, then the routine title.
 */
export function workoutDraftFromRoutine(
	routine: PlannedRoutine,
	discipline: string | null | undefined
): GymWorkoutDraft & { sets: RoutineDraftItem[] } {
	const sets: RoutineDraftItem[] = [];
	for (const block of prefillFromRoutine(routine)) {
		if (!namesAnExercise(block.name)) continue;
		for (const s of block.sets) {
			sets.push({
				exercise_name: block.name,
				reps: wholeOrNull(s.reps),
				weight_kg: s.weightKg,
				rpe: finiteOrNull(s.rpe)
			});
		}
	}
	return {
		title: asString(discipline ?? null) ?? asString(routine.title),
		duration_s: null,
		sets
	};
}
