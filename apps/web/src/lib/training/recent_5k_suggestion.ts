// The "build a plan from your recent 5K" suggestion a runner with no plan
// sees on Home. It picks the one measured 5K worth offering; the plan wizard
// then pre-fills its recent-5K field with it and leaves the "this reflects my
// fitness today" box unticked, so the time anchors no paces until the runner
// confirms it (the wizard's `recent5kConfirmed` gate).
//
// Dart twin: `apps/mobile_android/lib/recent_5k_suggestion.dart`.

/// How far back a measured 5K still counts as recent: eight weeks, the span a
/// plan's base phase assumes fitness holds over. Older times are what the
/// wizard's confirm box warns about, so they are not offered at all.
export const RECENT_5K_WINDOW_DAYS = 56;

/// The wizard's own bounds for a 5K time: 12:00 to 59:59, the range its
/// minutes field and the plan-request parser accept. A time outside it could
/// not be put in the field, so it is not offered.
export const RECENT_5K_MIN_S = 12 * 60;
export const RECENT_5K_MAX_S = 60 * 60 - 1;

const DAY_MS = 86_400_000;

export interface Recent5kCandidate {
	id: string;
	/// The run's start, as an ISO-8601 instant.
	startedAt: string;
	/// `runs.fastest_5k_s`: the fastest 5 km window measured inside the run.
	fastest5kS: number | null;
	activityType: string | null;
	isDnf: boolean | null;
}

export interface Recent5kSuggestion {
	runId: string;
	startedAt: string;
	seconds: number;
}

/// Whether a value is a 5K time the wizard can take.
export function isPlausibleRecent5k(seconds: unknown): seconds is number {
	return (
		typeof seconds === 'number' &&
		Number.isInteger(seconds) &&
		seconds >= RECENT_5K_MIN_S &&
		seconds <= RECENT_5K_MAX_S
	);
}

/// The 5K to suggest, or null. The fastest plausible `fastest_5k_s` among
/// runs started in the last [RECENT_5K_WINDOW_DAYS] days (not in the future),
/// ties going to the more recent run. Walks, hikes, rides and stroller runs
/// are left out, as is a DNF. `dismissedAt` is the moment the runner last
/// dismissed the suggestion: only a run started after it can bring the
/// suggestion back, so a newer 5K re-offers it and the one they waved away
/// does not. An unreadable stamp is treated as no dismissal.
export function pickRecent5k(
	runs: readonly Recent5kCandidate[],
	nowMs: number,
	dismissedAt: string | null,
): Recent5kSuggestion | null {
	const windowStartMs = nowMs - RECENT_5K_WINDOW_DAYS * DAY_MS;
	const dismissedMs = dismissedAt ? Date.parse(dismissedAt) : NaN;
	let best: Recent5kSuggestion | null = null;
	let bestMs = 0;
	for (const r of runs) {
		if (r.activityType != null && r.activityType !== 'run') continue;
		if (r.isDnf === true) continue;
		if (!isPlausibleRecent5k(r.fastest5kS)) continue;
		const ms = Date.parse(r.startedAt);
		if (!Number.isFinite(ms) || ms < windowStartMs || ms > nowMs) continue;
		if (Number.isFinite(dismissedMs) && ms <= dismissedMs) continue;
		const seconds = r.fastest5kS;
		if (best === null || seconds < best.seconds || (seconds === best.seconds && ms > bestMs)) {
			best = { runId: r.id, startedAt: r.startedAt, seconds };
			bestMs = ms;
		}
	}
	return best;
}
