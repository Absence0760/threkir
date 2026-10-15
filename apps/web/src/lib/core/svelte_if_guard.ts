/**
 * Svelte block nesting, resolved far enough to answer "is this offset inside
 * an `{#if}` branch whose condition names `flag`", at any depth. A token
 * guarded by `{#if flag}` two levels up is what a template actually relies
 * on, and a substring search cannot see it.
 *
 * `{:else}` leaves the guarded branch; `{:else if flag}` re-enters it. Only an
 * `{#if}` frame's `{:else}` is read that way — an `{#each}`'s empty-state
 * `{:else}` is not a condition on the flag.
 *
 * Used by the deploy-gate guards that pin a fail-closed flag's affordances
 * behind it (`runs/weigh_in_flag.test.ts`, `nutrition/weight_fluid_flag.test
 * .ts`); one copy, so a fix to the scan reaches every gate at once.
 */
export function insideIfBranch(template: string, flag: string): (i: number) => boolean {
	type Frame = { close: string; guarded: boolean };
	const token = /\{#(if|each|await|key|snippet)\b([^}]*)\}|\{:else([^}]*)\}|\{\/(if|each|await|key|snippet)\}/g;
	const named = new RegExp(`\\b${flag}\\b`);
	const stack: Frame[] = [];
	const marks: { at: number; depth: number }[] = [{ at: 0, depth: 0 }];
	let depth = 0;
	for (const m of template.matchAll(token)) {
		if (m[1]) {
			const guarded = m[1] === 'if' && named.test(m[2] ?? '');
			stack.push({ close: m[1], guarded });
			if (guarded) depth++;
		} else if (m[3] !== undefined) {
			const top = stack[stack.length - 1];
			if (top && top.close === 'if') {
				if (top.guarded) depth--;
				top.guarded = named.test(m[3]);
				if (top.guarded) depth++;
			}
		} else if (stack.pop()?.guarded) {
			depth--;
		}
		marks.push({ at: (m.index ?? 0) + m[0].length, depth });
	}
	return (i: number) => {
		let d = 0;
		for (const mark of marks) {
			if (mark.at > i) break;
			d = mark.depth;
		}
		return d > 0;
	};
}
