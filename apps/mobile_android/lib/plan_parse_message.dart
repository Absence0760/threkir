import 'l10n/gen/app_localizations.dart';
import 'plan_serialize.dart';

/// The localized reason a pasted plan could not be read. `plan_serialize.dart`
/// stops at a code and the cells it could not read, because the words around
/// them are a per-locale decision. Web's `planParseMessage` in
/// `i18n/plan_parse_message.ts` is the same glue; like the rate-limit
/// renderer it is per-platform and not part of the enforced lockstep.
String planParseErrorMessage(AppLocalizations l10n, PlanParseError e) {
  String p(String name) => e.params[name] ?? '';
  switch (e.code) {
    case PlanParseCode.badDistance:
      return l10n.planImportErrorBadDistance(p('cell'));
    case PlanParseCode.badPace:
      return l10n.planImportErrorBadPace(p('cell'));
    case PlanParseCode.duplicateColumn:
      return l10n.planImportErrorDuplicateColumn(p('column'));
    case PlanParseCode.missingColumn:
      return l10n.planImportErrorMissingColumn(p('column'));
    case PlanParseCode.raceNameTooLong:
      return l10n.planImportErrorRaceNameTooLong(p('name'), p('max'));
    case PlanParseCode.badRacePriority:
      return l10n.planImportErrorBadRacePriority(p('cell'));
    case PlanParseCode.badGoalTime:
      return l10n.planImportErrorBadGoalTime(p('cell'));
    case PlanParseCode.badWeek:
      return l10n.planImportErrorBadWeek(p('cell'));
    case PlanParseCode.badDate:
      return l10n.planImportErrorBadDate(p('cell'));
    case PlanParseCode.unknownKind:
      return l10n.planImportErrorUnknownKind(p('cell'));
    case PlanParseCode.raceFieldsOnNonRace:
      return l10n.planImportErrorRaceFieldsOnNonRace(p('date'));
    case PlanParseCode.noRows:
      return l10n.planImportErrorNoRows;
    case PlanParseCode.noGoalDistance:
      return l10n.planImportErrorNoGoalDistance;
    case PlanParseCode.beforeStart:
      return l10n.planImportErrorBeforeStart(p('date'), p('start'));
    case PlanParseCode.notJson:
      return l10n.planImportErrorNotJson;
    case PlanParseCode.noWorkoutsArray:
      return l10n.planImportErrorNoWorkoutsArray;
    case PlanParseCode.badJsonShape:
      return l10n.planImportErrorBadJsonShape;
    case PlanParseCode.badTaperStamp:
      return l10n.planImportErrorBadTaperStamp(p('value'), p('date'));
  }
}
