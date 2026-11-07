/// A pace difference, stored as seconds per km, in the unit the pace beside
/// it is read in, with that unit spelled out: "+16s/mi", "−10s/km". A bare
/// "+428s" next to a /mi target was s/km and read as s/mi (issue #1300).
/// The Dart twin is `UnitFormat.paceDelta` in
/// apps/mobile_android/lib/preferences.dart.

import { paceToleranceToUnit } from './pace_format';

export function paceDeltaLabel(deltaSecPerKm: number, unit: 'km' | 'mi'): string {
	const d = paceToleranceToUnit(deltaSecPerKm, unit);
	const sign = d > 0 ? '+' : d < 0 ? '−' : '';
	return `${sign}${Math.abs(d)}s/${unit}`;
}
