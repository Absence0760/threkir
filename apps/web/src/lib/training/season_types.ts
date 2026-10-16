// The race list a multi-race season is planned from (issue #1181). The
// season request extracts it from the runner's description, the runner
// confirms or edits it, and the season builder turns it into one chained plan
// per A race with the B / C races attached to the plan they fall inside.

export type SeasonRacePriority = 'A' | 'B' | 'C';

export interface SeasonRace {
	name: string;
	/// ISO `yyyy-mm-dd`.
	date: string;
	distanceM: number;
	priority: SeasonRacePriority;
	goalTimeSec: number | null;
}

export interface SeasonRequestResult {
	races: SeasonRace[];
	/// Why a race holds what it holds when it is not simply what the runner
	/// wrote: one key per adjustment, rendered as a localized line.
	assumptions: string[];
}
