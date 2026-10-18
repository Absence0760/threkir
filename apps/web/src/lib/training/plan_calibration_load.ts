import { supabase } from '#lib/core/supabase.ts';
import { dbError, thrownMessage } from '#lib/core/supabase_error.ts';
import { loadSettings } from '#lib/settings/settings.ts';
import { planCalibrationFrom, type PlanCalibration } from './plan_calibration.ts';

/// Each read is its own failure domain: a failed profile read must not drop
/// the setting, nor a failed settings read the age.
export async function loadPlanCalibration(userId: string): Promise<PlanCalibration> {
	const [profile, settings] = await Promise.all([
		(async () => {
			try {
				const { data, error } = await supabase.rpc('get_my_profile', undefined, { get: true }).maybeSingle();
				if (error) throw dbError(error);
				return data as unknown;
			} catch (e) {
				console.error('plan calibration: profile read failed', { message: thrownMessage(e) });
				return undefined;
			}
		})(),
		loadSettings(userId).catch((e: unknown) => {
			console.error('plan calibration: settings read failed', { message: thrownMessage(e) });
			return null;
		}),
	]);
	return planCalibrationFrom(profile, settings, Date.now());
}
