/// A fixed-cadence poll that runs only while the tab is visible.
///
/// The interval is cleared when the document goes hidden, so a background tab
/// sends nothing, and on becoming visible again the tick runs at once and the
/// interval restarts: a tab brought back after a while catches up immediately
/// instead of waiting out a full period. Returns the teardown, which a
/// Svelte `$effect` returns so the poll stops on navigation.
///
/// Framework-free with injectable timers so it is unit-testable under
/// `npx tsx --test`.

import type { VisibilitySource } from '../format/local_day_ticker';

export interface VisiblePollDeps {
	setInterval: (fn: () => void, ms: number) => unknown;
	clearInterval: (handle: unknown) => void;
	/// Null where there is no document (the server renderer): the poll then
	/// runs unconditionally.
	doc: VisibilitySource | null;
}

const browserDeps = (): VisiblePollDeps => ({
	setInterval: (fn, ms) => globalThis.setInterval(fn, ms),
	clearInterval: (h) => globalThis.clearInterval(h as ReturnType<typeof setInterval>),
	doc: typeof document === 'undefined' ? null : document
});

export function startVisiblePoll(
	tick: () => void,
	ms: number,
	deps: VisiblePollDeps = browserDeps()
): () => void {
	let timer: unknown = null;
	const visible = () => deps.doc === null || deps.doc.visibilityState === 'visible';
	const start = () => {
		if (timer === null) timer = deps.setInterval(tick, ms);
	};
	const stop = () => {
		if (timer !== null) deps.clearInterval(timer);
		timer = null;
	};
	const onVisibility = () => {
		if (visible()) {
			if (timer !== null) return;
			tick();
			start();
		} else {
			stop();
		}
	};

	if (visible()) start();
	deps.doc?.addEventListener('visibilitychange', onVisibility);
	return () => {
		stop();
		deps.doc?.removeEventListener('visibilitychange', onVisibility);
	};
}
