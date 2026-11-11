/// Where Grisnir may appear, decided once so every surface asks the same
/// questions (apps/web/static/brand/grisnir/README.md): the runner's universal
/// `show_mascot` (on unless literally `false`), never an error or failure
/// state, and at most one milestone moment per run.
///
/// `pickMilestone` is a parity pair with
/// apps/mobile_android/lib/mascot.dart's `pickMilestone`.

import { effective, type LoadedSettings } from '#lib/settings/settings_overlay.ts';
import type { MessageKey } from '#lib/i18n/messages.ts';

export function mascotShownIn(settings: LoadedSettings): boolean {
	return effective<unknown>(settings, 'show_mascot', true) !== false;
}

/// An empty state shows him only when its caller opted in, the runner's
/// setting is known and on, and the state is not an error: a `danger` tone or
/// an alert role is a failure being reported, and a mascot there reads as the
/// app making light of it.
export function emptyStateShowsMascot(opts: {
	mascot: boolean | undefined;
	tone: string | undefined;
	role: unknown;
	prefShown: boolean | null;
}): boolean {
	if (!opts.mascot || opts.prefShown !== true) return false;
	if (opts.tone === 'danger') return false;
	if (opts.role === 'alert' || opts.role === 'alertdialog') return false;
	return true;
}

export type MilestoneKind = 'first_run' | 'first_5k' | 'badge' | 'best' | 'longest';

export interface MilestoneFacts {
	/// Every run the runner has, this one included.
	totalRuns: number;
	runDistanceM: number;
	/// The longest distance across all of them, this one included.
	longestRunM: number;
	/// The personal records this run set (`PrCardEntry`'s distance and kind).
	records: readonly { distance: string; kind: 'improved' | 'first' | 'held' }[];
	/// Whether an achievement row names this run as its source.
	badgeEarned: boolean;
}

/// The one moment a run earns, most notable first, or null. A new best is an
/// improved time at a PR distance (a faster pace over it); "first" at 5K is
/// the first time the runner covered one. The longest run needs an earlier
/// run to be longer than.
export function pickMilestone(f: MilestoneFacts): MilestoneKind | null {
	if (f.totalRuns === 1) return 'first_run';
	if (f.records.some((r) => r.distance === '5k' && r.kind === 'first')) return 'first_5k';
	if (f.badgeEarned) return 'badge';
	if (f.records.some((r) => r.kind === 'improved')) return 'best';
	if (f.totalRuns > 1 && f.runDistanceM > 0 && f.runDistanceM >= f.longestRunM) return 'longest';
	return null;
}

export const MILESTONE_LINE: Record<MilestoneKind, MessageKey> = {
	first_run: 'mascot.milestoneFirstRun',
	first_5k: 'mascot.milestoneFirst5k',
	badge: 'mascot.milestoneBadge',
	best: 'mascot.milestoneBest',
	longest: 'mascot.milestoneLongest',
};
