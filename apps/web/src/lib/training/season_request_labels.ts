// The localized line for each season-request assumption key. The wire keys
// are `SEASON_REQUEST_ASSUMPTIONS` (season_request/races.ts); typed off that
// tuple, so a key added there fails this map to compile until it has a label.
// Mirrored on mobile by `seasonAssumptionLabel` in season_request_client.dart.

import type { MessageKey } from '../i18n/messages';
import type { SeasonRequestAssumption } from './season_request/races';

const SEASON_ASSUMPTION_KEYS: Record<SeasonRequestAssumption, MessageKey> = {
	race_dropped_invalid: 'planEditor.seasonAssumptionRaceDroppedInvalid',
	race_dropped_date: 'planEditor.seasonAssumptionRaceDroppedDate',
	race_dropped_distance: 'planEditor.seasonAssumptionRaceDroppedDistance',
	race_date_next_year: 'planEditor.seasonAssumptionRaceDateNextYear',
	goal_time_dropped: 'planEditor.seasonAssumptionGoalTimeDropped',
	race_duplicate_merged: 'planEditor.seasonAssumptionRaceDuplicateMerged',
	races_capped: 'planEditor.seasonAssumptionRacesCapped',
	priority_default: 'planEditor.seasonAssumptionPriorityDefault',
	priority_a_assigned: 'planEditor.seasonAssumptionPriorityAAssigned',
};

/// The message key for one assumption the season request returned — render
/// it with `t(...)`. Null for a key this build does not know, which the
/// client already refuses, so a caller can skip it rather than show a raw key.
export function seasonAssumptionMessageKey(assumption: string): MessageKey | null {
	return Object.hasOwn(SEASON_ASSUMPTION_KEYS, assumption)
		? SEASON_ASSUMPTION_KEYS[assumption as SeasonRequestAssumption]
		: null;
}
