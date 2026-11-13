// What `UnsavedChangesGuard` does with one attempted navigation. Pure, so the
// order of its checks is unit-tested without a router.
//
// - `allow`: let it through (the guard's own confirmed leave, or nothing to lose).
// - `busy`: a create or save is on the wire; cancel and say so (a toast), so a
//   create never finishes out of sight (decisions § 2500).
// - `ask`: unsaved input; cancel and offer "Discard changes?".
// - `browser`: closing or reloading the tab; cancel, which SvelteKit turns
//   into the browser's own beforeunload prompt, with nothing of ours to draw.
export type LeaveDecision = 'allow' | 'busy' | 'ask' | 'browser';

export function leaveDecision(input: {
	leaving: boolean;
	busy: boolean;
	dirty: boolean;
	unload: boolean;
}): LeaveDecision {
	if (input.leaving) return 'allow';
	if (!input.busy && !input.dirty) return 'allow';
	if (input.unload) return 'browser';
	return input.busy ? 'busy' : 'ask';
}
