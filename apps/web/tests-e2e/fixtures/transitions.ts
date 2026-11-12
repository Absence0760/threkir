import type { Locator } from '@playwright/test';

/**
 * Resolve once every CSS transition on `target` (and, by default, its subtree)
 * has stopped, so a following `getComputedStyle` read sees the
 * settled value rather than a frame of the fade.
 *
 * A computed style read straight after a class flip or a hover returns
 * wherever the transition happens to be: the public header's glass read 0.176
 * on its way to 0.8 on a loaded CI runner (run 37709672474). A fixed
 * `waitForTimeout` sized to the transition only moves the race. This waits on
 * the thing the read actually depends on.
 *
 * `getAnimations()` flushes pending style first, so a transition the caller
 * just triggered is already in the list. A transition that is cancelled rather
 * than completed (a re-render restarting it) rejects `finished` with an
 * AbortError and is replaced by a new one, so settle every pass and look again
 * until nothing is running. Only transitions are awaited: an infinite
 * keyframe animation (a spinner, a live dot) never finishes and would hang.
 */
export async function settleTransitions(
	target: Locator,
	{ subtree = true }: { subtree?: boolean } = {}
): Promise<void> {
	const settled = await target.evaluate(async (el, subtree) => {
		const running = () =>
			el.getAnimations({ subtree }).filter((a) => a instanceof CSSTransition);
		for (let pass = 0; pass < 10; pass++) {
			const now = running();
			if (now.length === 0) return true;
			await Promise.allSettled(now.map((a) => a.finished));
		}
		return running().length === 0;
	}, subtree);
	if (!settled) throw new Error('transitions kept restarting and never settled');
}
