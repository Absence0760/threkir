/// The sentence a pasted plan's parse refusal reads as, from the catalogue.
///
/// `training/plan_serialize.ts` (the parity half) throws a `PlanParseError`
/// carrying a code and the cells it could not read; which words wrap them is a
/// per-locale decision, so the parser stops at the code. Mobile's
/// `planParseErrorMessage(l10n, e)` in `plan_parse_message.dart` is the same
/// glue; like `rate_limit_message.ts` it is per-platform and not part of the
/// enforced lockstep.

import type { MessageKey } from './messages';
import type { Translate } from './rate_limit_message';
import { PlanParseError, type PlanParseCode } from '../training/plan_serialize';

const KEY: Record<PlanParseCode, MessageKey> = {
	badDistance: 'planImport.badDistance',
	badPace: 'planImport.badPace',
	duplicateColumn: 'planImport.duplicateColumn',
	missingColumn: 'planImport.missingColumn',
	raceNameTooLong: 'planImport.raceNameTooLong',
	badRacePriority: 'planImport.badRacePriority',
	badGoalTime: 'planImport.badGoalTime',
	badWeek: 'planImport.badWeek',
	badDate: 'planImport.badDate',
	unknownKind: 'planImport.unknownKind',
	raceFieldsOnNonRace: 'planImport.raceFieldsOnNonRace',
	noRows: 'planImport.noRows',
	noGoalDistance: 'planImport.noGoalDistance',
	beforeStart: 'planImport.beforeStart',
	notJson: 'planImport.notJson',
	noWorkoutsArray: 'planImport.noWorkoutsArray',
	badJsonShape: 'planImport.badJsonShape',
	badTaperStamp: 'planImport.badTaperStamp',
};

/// The localized reason, or null when `e` is not a parse refusal.
export function planParseMessage(e: unknown, t: Translate): string | null {
	if (!(e instanceof PlanParseError)) return null;
	return t(KEY[e.code], { ...e.params });
}
