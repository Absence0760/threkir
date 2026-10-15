// Groups a logged workout's sets (already in set_index order) into the
// per-exercise blocks the owner's /gym/[id] detail and the public
// /share/workout/[id] page both render.
//
// Pure — no Svelte / Supabase dependencies, so it runs under `npx tsx --test`.
// Web-only: no Dart twin.

import { normaliseExerciseName } from './gym_prs';

export interface ExerciseBlock<S> {
	/// Display spelling of the block's first set.
	name: string;
	/// Canonical grouping key (`normaliseExerciseName`).
	key: string;
	/// Index of the block's first set in the input — the block's `{#each}`
	/// key. Neither `name` nor `key` can be one: a superset or circuit logs the
	/// same lift in non-consecutive sets, so one exercise yields several blocks.
	start: number;
	sets: S[];
}

/// Consecutive sets of the same exercise (compared on the canonical key, never
/// the spelling) form one block; a lift that reappears after another exercise
/// opens a new block rather than rejoining its earlier one, so the rendered
/// order is the order the sets were logged in.
export function groupExerciseBlocks<S extends { exercise_name: string }>(
	sets: readonly S[],
): ExerciseBlock<S>[] {
	const out: ExerciseBlock<S>[] = [];
	sets.forEach((s, i) => {
		const last = out[out.length - 1];
		const key = normaliseExerciseName(s.exercise_name);
		if (last && last.key === key) last.sets.push(s);
		else out.push({ name: s.exercise_name, key, start: i, sets: [s] });
	});
	return out;
}
