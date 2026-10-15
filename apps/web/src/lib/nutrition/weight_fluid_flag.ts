/**
 * Fail-closed deploy gate for the weight-based fluid rate — the "Fluid from
 * body weight" toggle on the roadbook and `/nutrition/fuel` (decisions § 1976).
 *
 * The rate reads the runner's consented `body_metrics` weight, which is a new
 * Art 9 use of health data (fluid planning), so CISO + counsel review it
 * against the health-data consent copy before it reaches real users
 * (decisions § 150). Unset / empty / "false" / "0" → off: neither page reads a
 * body weight at all, the toggle never renders, and the flat per-hour rate
 * stands whatever `?bw=1` a link carries.
 *
 * The mobile twin `apps/mobile_android/lib/weight_fluid_flag.dart` reads
 * `WEIGHT_FLUID_ENABLED`, the dropped-prefix spelling of this key. There is no
 * server half: the rate is computed on the client from a read RLS already
 * scopes to the runner's own rows.
 */
import { PUBLIC_WEIGHT_FLUID_ENABLED } from '$app/env/public';
import { isTruthyFlagValue } from '../core/env_flag';

export function weightFluidEnabled(): boolean {
	return isTruthyFlagValue(PUBLIC_WEIGHT_FLUID_ENABLED);
}
