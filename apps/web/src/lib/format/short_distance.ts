/// A distance in the unit a runner reads at that size: miles from one mile up
/// and yards below it, kilometres from one kilometre up and metres below it.
/// Two decimals on the large unit, a grouped whole number on the small one.
///
/// Pure (explicit unit + locale) so it unit-tests without the Svelte compiler;
/// `formatDistance` in units.svelte.ts supplies the preference signal. The
/// Dart twin is `UnitFormat.shortDistance` in
/// apps/mobile_android/lib/preferences.dart.

import { formatDecimal, formatInteger } from './number';

const METRES_PER_MILE = 1609.344;
const YARDS_PER_METRE = 1.09361;

export function formatShortDistance(metres: number, unit: 'km' | 'mi', locale?: string): string {
	if (unit === 'mi') {
		const miles = metres / METRES_PER_MILE;
		if (miles >= 1) return `${formatDecimal(miles, 2, locale)} mi`;
		return `${formatInteger(Math.round(metres * YARDS_PER_METRE), locale)} yd`;
	}
	if (metres >= 1000) return `${formatDecimal(metres / 1000, 2, locale)} km`;
	return `${formatInteger(Math.round(metres), locale)} m`;
}
