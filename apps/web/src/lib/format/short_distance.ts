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

/// A badge or milestone threshold in the reader's unit: "42.2 km" / "26.2 mi",
/// "50 km" / "31.1 mi", "1,000 km" / "621 mi". `digits` is 1 for a race
/// distance and 0 for a total; a value that rounds to a whole number drops its
/// ".0". Dart twin: `UnitFormat.thresholdDistance`.
export function formatThresholdDistance(
	metres: number,
	unit: 'km' | 'mi',
	digits: 0 | 1,
	locale?: string,
): string {
	const v = unit === 'mi' ? metres / METRES_PER_MILE : metres / 1000;
	const r = digits === 0 ? Math.round(v) : Math.round(v * 10) / 10;
	const n = Number.isInteger(r) ? formatInteger(r, locale) : formatDecimal(r, 1, locale);
	return `${n} ${unit}`;
}
