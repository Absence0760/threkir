/**
 * Fail-closed deploy gate for heart-rate prescription and medication-affected
 * heart rate (issue #1186, decisions § 2085).
 *
 * Three Art 9 surfaces sit behind it: the bpm target on a planned workout
 * (editor, workout detail, the coach's view, the live runner), the "heart rate
 * is medication-affected" setting with its low-confidence label on the
 * training-load chart, and the easy-run HR-drift flag on the coach roster.
 * CISO + counsel review them against the health-data consent copy before they
 * reach real users (decisions § 150). Unset / empty / "false" / "0" → off:
 * none of the three renders, and nothing writes a bpm target or the setting.
 *
 * Defence in depth: the database refuses a bpm target unless the plan owner
 * holds `health_data_consent_at` (migration 20270912000001), computes the
 * roster drift only for a consented athlete, and the consent withdrawal clears
 * both. The flag gates the UI; consent gates the data.
 *
 * The mobile twin `apps/mobile_android/lib/hr_prescription_flag.dart` reads
 * `HR_PRESCRIPTION_ENABLED`, the dropped-prefix spelling of this key.
 */
import { PUBLIC_HR_PRESCRIPTION_ENABLED } from '$app/env/public';
import { isTruthyFlagValue } from '../core/env_flag';

export function hrPrescriptionEnabled(): boolean {
	return isTruthyFlagValue(PUBLIC_HR_PRESCRIPTION_ENABLED);
}
