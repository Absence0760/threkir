/**
 * The heart-rate prescription gate, read from the server (issue #1186,
 * decisions § 2092, § 2108).
 *
 * Three Art 9 surfaces sit behind it: the bpm target on a planned workout
 * (editor, workout detail, the coach's view), the "heart rate is
 * medication-affected" setting with its low-confidence label on the
 * training-load chart, and the easy-run HR-drift flag on the coach roster.
 * CISO + counsel review them against the health-data consent copy before they
 * reach real users (decisions § 150).
 *
 * The gate is the `hr_prescription` row in `private.feature_flags`, which the
 * database itself enforces on every write and on the roster read. The client
 * asks the same row through `public.hr_prescription_enabled()` rather than
 * reading a build flag of its own, so the surfaces can never be on while the
 * server refuses what they write. Fail-closed: a failed read is "off" and is
 * not cached, so a later mount can find out.
 *
 * The mobile twin is `apps/mobile_android/lib/hr_prescription_gate.dart`.
 */
import { supabase } from '../core/supabase';

let probe: Promise<boolean> | null = null;

export function hrPrescriptionEnabled(): Promise<boolean> {
	if (probe) return probe;
	const read = (async () => {
		try {
			const { data, error } = await supabase.rpc('hr_prescription_enabled', undefined, { get: true });
			if (error) {
				probe = null;
				return false;
			}
			return data === true;
		} catch {
			probe = null;
			return false;
		}
	})();
	probe = read;
	return read;
}
