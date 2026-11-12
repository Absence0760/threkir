/// Keeps a page's "today" current across local midnight, the way /nutrition
/// and mobile's plan screens do (decisions § 2101). A `$derived(todayISO())`
/// has no reactive input, so it is computed once and a tab left open overnight
/// keeps calling yesterday "today".
///
/// Two triggers, one wakeup a day: a single timeout armed for the next local
/// midnight, calendar-stepped by `msUntilNextLocalMidnight` so a DST day still
/// lands on midnight, and a re-check on `visibilitychange`, window `focus`
/// and `pageshow` for a tab whose timer the browser throttled or the machine
/// slept through (a tab left visible through a suspend fires no
/// visibilitychange on wake, and one restored from the back/forward cache
/// fires only pageshow). Never a polling interval.

import { msUntilNextLocalMidnight } from '../nutrition/diary_day';
import { formatISO } from '../training/training';

export interface DayTickerDeps {
	now: () => Date;
	setTimeout: (fn: () => void, ms: number) => unknown;
	clearTimeout: (handle: unknown) => void;
	/// The document whose visibility re-checks the day; null where there is
	/// none (the server renderer).
	doc: VisibilitySource | null;
	/// The window whose `focus` and `pageshow` re-check the day; null where
	/// there is none.
	win: WakeSource | null;
}

export interface WakeSource {
	addEventListener(type: 'focus' | 'pageshow', fn: () => void): void;
	removeEventListener(type: 'focus' | 'pageshow', fn: () => void): void;
}

export interface VisibilitySource {
	addEventListener(type: 'visibilitychange', fn: () => void): void;
	removeEventListener(type: 'visibilitychange', fn: () => void): void;
	readonly visibilityState: string;
}

const browserDeps = (): DayTickerDeps => ({
	now: () => new Date(),
	setTimeout: (fn, ms) => globalThis.setTimeout(fn, ms),
	clearTimeout: (h) => globalThis.clearTimeout(h as ReturnType<typeof setTimeout>),
	doc: typeof document === 'undefined' ? null : document,
	win: typeof window === 'undefined' ? null : window,
});

/// Calls `onDay` with the local yyyy-mm-dd whenever it changes, starting from
/// the current day's value at the call. Returns the teardown.
export function startLocalDayTicker(
	onDay: (iso: string) => void,
	deps: DayTickerDeps = browserDeps(),
): () => void {
	let current = formatISO(deps.now());
	let timer: unknown = null;

	const sync = () => {
		const iso = formatISO(deps.now());
		if (iso !== current) {
			current = iso;
			onDay(iso);
		}
		arm();
	};
	const arm = () => {
		if (timer !== null) deps.clearTimeout(timer);
		timer = deps.setTimeout(sync, msUntilNextLocalMidnight(deps.now()));
	};
	const onVisibility = () => {
		if (deps.doc?.visibilityState === 'visible') sync();
	};

	onDay(current);
	arm();
	deps.doc?.addEventListener('visibilitychange', onVisibility);
	deps.win?.addEventListener('focus', sync);
	deps.win?.addEventListener('pageshow', sync);
	return () => {
		if (timer !== null) deps.clearTimeout(timer);
		timer = null;
		deps.doc?.removeEventListener('visibilitychange', onVisibility);
		deps.win?.removeEventListener('focus', sync);
		deps.win?.removeEventListener('pageshow', sync);
	};
}
