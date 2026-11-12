/**
 * The athlete's side of the coach assistant (issue #1215 Phase 4, migration
 * 20271210001217): a consent per coaching link, at a version of its own
 * ladder. The copy at a version names every lane `COACH_ASSIST_REGISTRY`
 * sends from it; a later version only adds to what an earlier one named.
 *
 * Must equal `coach_assist_consent_current_version()`; consent.test.ts reads
 * the migration.
 */
export const COACH_ASSIST_CONSENT_VERSION = 1;

/** Whether a stored consent covers lanes sent from `required`. Fail-closed. */
export function coachAssistConsentCovers(stored: unknown, required: number): boolean {
	return (
		typeof stored === 'number' &&
		Number.isInteger(stored) &&
		stored >= required &&
		stored <= COACH_ASSIST_CONSENT_VERSION
	);
}
