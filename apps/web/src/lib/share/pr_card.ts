// The personal records one run set, as the PR share card prints them. A TS↔Dart
// parity pair with apps/mobile_android/lib/pr_card.dart (docs/architecture/
// parity_pairs.md), so both platforms offer the same brackets in the same order
// with the same improvement.
//
// Two sources, both owner-only: `personal_record_improvements`, the log the
// refresher writes when a run beats the cache (with the time it replaced), and
// `personal_records`, the cache itself. A record the run still holds but that
// predates the log has no known previous time, so it prints as a record with no
// "faster by" line rather than as a first.

import { formatShareDuration } from './run_share_stats';

export const PR_BRACKETS = ['1_mile', '5k', '8k', '10k', '12k', 'half_marathon', 'marathon'] as const;
export type PrBracket = (typeof PR_BRACKETS)[number];

/// The bracket's nominal distance, which orders the card's brackets longest
/// first and is the distance the card prints.
export const PR_BRACKET_METRES: Record<PrBracket, number> = {
	'1_mile': 1609.344,
	'5k': 5000,
	'8k': 8000,
	'10k': 10000,
	'12k': 12000,
	half_marathon: 21097.5,
	marathon: 42195,
};

export interface PrImprovementRow {
	distance: string;
	best_time_s: number;
	previous_time_s: number | null;
}

export interface PrHeldRow {
	distance: string;
	best_time_s: number;
}

/// `improved` beat an earlier record; `first` was the first time in that
/// bracket; `held` is a record the run holds from before the log existed.
export type PrCardKind = 'improved' | 'first' | 'held';

export interface PrCardEntry {
	distance: PrBracket;
	timeS: number;
	previousS: number | null;
	kind: PrCardKind;
}

function isBracket(d: string): d is PrBracket {
	return (PR_BRACKETS as readonly string[]).includes(d);
}

/// Every bracket the run set, longest first. A logged improvement wins over the
/// cache row for the same bracket, since only the log knows what it beat.
export function prCardEntries(improvements: readonly PrImprovementRow[], held: readonly PrHeldRow[]): PrCardEntry[] {
	const byBracket = new Map<PrBracket, PrCardEntry>();
	for (const row of held) {
		if (!isBracket(row.distance) || !(row.best_time_s > 0)) continue;
		byBracket.set(row.distance, { distance: row.distance, timeS: row.best_time_s, previousS: null, kind: 'held' });
	}
	for (const row of improvements) {
		if (!isBracket(row.distance) || !(row.best_time_s > 0)) continue;
		const previous = row.previous_time_s != null && row.previous_time_s > row.best_time_s ? row.previous_time_s : null;
		byBracket.set(row.distance, {
			distance: row.distance,
			timeS: row.best_time_s,
			previousS: previous,
			kind: previous == null ? 'first' : 'improved',
		});
	}
	return [...byBracket.values()].sort((a, b) => PR_BRACKET_METRES[b.distance] - PR_BRACKET_METRES[a.distance]);
}

/// Seconds faster than the record it beat, or null when nothing was beaten.
export function prImprovementSeconds(entry: PrCardEntry): number | null {
	return entry.previousS == null ? null : entry.previousS - entry.timeS;
}

/// The improvement as the card prints it ("00:42"), or null.
export function formatPrImprovement(entry: PrCardEntry): string | null {
	const s = prImprovementSeconds(entry);
	return s == null ? null : formatShareDuration(s);
}
