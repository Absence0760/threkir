// P4 "next target" hints for a logged session that ran a routine
// (gym_programming.md): one suggestion per scheme-tracked lift, from THIS
// session's logged sets. Pure suggestion — never auto-applied.
//
// Pure — no Svelte / Supabase dependencies, so it runs under `npx tsx --test`.
// Dart twin: `apps/mobile_android/lib/next_target_hints.dart` — keep the
// algorithm, edge cases, outputs, and test counts in lockstep.

import { normaliseExerciseName } from './gym_prs';
import { nextPrescription, type ProgressionScheme, type ProgressionSetLike } from './gym_progression';
import { progressionParamsWithStreak, type DatedLoggedSet } from './progression_prefill';
import type { NextTargetHint } from './gym_session_types';

export interface HintRoutineExercise {
	exercise_name: string;
	progression: ProgressionScheme;
	progression_params: Record<string, unknown> | null;
	sets: ReadonlyArray<{ target_reps_min: number | null; target_reps_max: number | null }>;
}

export interface HintLoggedSet extends ProgressionSetLike {
	exercise_name: string;
}

/// One hint per lift, never one per routine block. The logged sets are pooled
/// by the canonical key, so a lift programmed into two blocks (a heavy top set
/// then back-offs) would otherwise yield two hints judged on the same sets —
/// and two rows sharing the review's `exerciseKey` key. The first block that
/// produces a suggestion speaks for the lift.
export function buildNextTargetHints(input: {
	exercises: readonly HintRoutineExercise[];
	sets: readonly HintLoggedSet[];
	history: DatedLoggedSet[];
}): NextTargetHint[] {
	const setsByKey = new Map<string, ProgressionSetLike[]>();
	for (const s of input.sets) {
		const key = normaliseExerciseName(s.exercise_name);
		if (key === '') continue;
		const list = setsByKey.get(key) ?? [];
		list.push({ reps: s.reps, weight_kg: s.weight_kg, rpe: s.rpe, set_type: s.set_type });
		setsByKey.set(key, list);
	}

	const out: NextTargetHint[] = [];
	const hinted = new Set<string>();
	for (const ex of input.exercises) {
		if (ex.progression === 'none') continue;
		const key = normaliseExerciseName(ex.exercise_name);
		if (hinted.has(key)) continue;
		const lastSets = setsByKey.get(key);
		if (!lastSets || lastSets.length === 0) continue;
		const firstSet = ex.sets[0];
		const sug = nextPrescription({
			scheme: ex.progression,
			lastSets,
			targetRepsMin: firstSet?.target_reps_min ?? null,
			targetRepsMax: firstSet?.target_reps_max ?? null,
			// The 5×5 back-off needs a miss count across sessions, which no
			// authored params bag carries — the history supplies it.
			params: progressionParamsWithStreak({
				scheme: ex.progression,
				params: ex.progression_params,
				targetRepsMin: firstSet?.target_reps_min ?? null,
				targetRepsMax: firstSet?.target_reps_max ?? null,
				history: input.history,
				exerciseName: ex.exercise_name,
			}),
		});
		if (sug.reason === 'none') continue;

		let topKg: number | null = null;
		let topReps: number | null = null;
		for (const s of lastSets) {
			if (s.weight_kg != null && s.weight_kg > 0 && (topKg == null || s.weight_kg > topKg)) {
				topKg = s.weight_kg;
				topReps = s.reps;
			}
		}
		hinted.add(key);
		out.push({
			exerciseKey: key,
			exerciseName: ex.exercise_name,
			suggestedWeightKg: sug.suggestedWeightKg,
			suggestedRepsMin: sug.suggestedRepsMin,
			suggestedRepsMax: sug.suggestedRepsMax,
			currentTopKg: topKg,
			currentTopReps: topReps,
			reason: sug.reason,
		});
	}
	return out;
}
