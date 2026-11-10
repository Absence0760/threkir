/// The athlete's side of the coach assistant (issue #1215 Phase 4, migration
/// 20271210001217): a consent per coaching link, at a version of its own
/// ladder. The copy at a version names every lane the drafting endpoint sends
/// from it; a later version only adds to what an earlier one named.
///
/// Must equal the SQL `coach_assist_consent_current_version()` and web's
/// `COACH_ASSIST_CONSENT_VERSION` (`coach/assist/consent.ts`);
/// `test/coach_assist_consent_test.dart` reads the migration.
library;

const int kCoachAssistConsentVersion = 1;
