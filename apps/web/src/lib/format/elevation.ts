/// Cumulative elevation gain as whole metres or whole feet, grouped by the
/// locale: "10,000 ft" (en), "10.000 ft" (de). Whole units because sub-metre
/// precision on cumulative gain is the GPS-noise floor.
///
/// Pure (explicit unit + locale) so it unit-tests without the Svelte compiler;
/// `formatElevation` in units.svelte.ts supplies the preference signal. The
/// Dart twin is `UnitFormat.elevation` / `UnitFormat.elevationValue` in
/// apps/mobile_android/lib/preferences.dart.

import { formatDecimal, formatInteger } from './number';

const FEET_PER_METRE = 3.28084;

export function formatElevationValue(metres: number, unit: 'km' | 'mi', locale?: string): string {
	const value = unit === 'mi' ? metres * FEET_PER_METRE : metres;
	return formatInteger(Math.round(value), locale);
}

export function formatElevationIn(
	metres: number | null | undefined,
	unit: 'km' | 'mi',
	locale?: string,
): string {
	if (metres == null) return '—';
	return `${formatElevationValue(metres, unit, locale)} ${unit === 'mi' ? 'ft' : 'm'}`;
}

/// A stride length as metres or feet to two decimals: "1.18 m" / "3.87 ft".
/// Same metre-to-foot factor as elevation, so an imperial reader never sees
/// one run-detail length in metres. Dart twin: `UnitFormat.strideLength`.
export function formatStrideLengthIn(
	metres: number | null | undefined,
	unit: 'km' | 'mi',
	locale?: string,
): string {
	if (metres == null) return '—';
	const value = unit === 'mi' ? metres * FEET_PER_METRE : metres;
	return `${formatDecimal(value, 2, locale)} ${unit === 'mi' ? 'ft' : 'm'}`;
}
