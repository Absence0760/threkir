// Locale-aware number formatting (i18n-readiness W-15). The unit
// formatters in units.svelte.ts previously used `.toFixed(N)`, which
// always emits a period decimal separator and never groups thousands —
// wrong for the comma-decimal locales (de/es/fr/pt-BR: `5,21 km`) and the
// space/locale grouping ones (fr: `1 234`). These pure helpers wrap
// Intl.NumberFormat so the same value renders correctly per locale.
//
// Kept pure (plain .ts, explicit `locale` arg) so it unit-tests under
// `tsx --test`; the reactive caller (units.svelte.ts) passes the active
// UI locale from the i18n runtime. Intl.NumberFormat construction is
// relatively expensive, so instances are memoised by (locale, digits) —
// the responsiveness guard, since these run on every distance/pace cell.
//
// Pace ("m:ss") is deliberately NOT routed through here: it is athletic
// notation, intentionally locale-neutral (see units.svelte.ts).

const cache = new Map<string, Intl.NumberFormat>();

function formatter(locale: string | undefined, min: number, max: number): Intl.NumberFormat {
	const key = `${locale ?? ''}|${min}|${max}`;
	let nf = cache.get(key);
	if (!nf) {
		nf = new Intl.NumberFormat(locale, {
			minimumFractionDigits: min,
			maximumFractionDigits: max,
		});
		cache.set(key, nf);
	}
	return nf;
}

/// Fixed-fraction decimal (the locale-aware replacement for `toFixed`):
/// `formatDecimal(5.21, 2, 'de')` → `'5,21'`, `(1234.5, 1, 'en')` →
/// `'1,234.5'`. `digits` pins both the minimum and maximum fraction
/// digits so the width matches the old `toFixed(digits)` exactly.
export function formatDecimal(value: number, digits: number, locale?: string): string {
	return formatLabel(formatter(locale, digits, digits), value);
}

/// Grouped integer: `formatInteger(1234, 'de')` → `'1.234'`,
/// `(1234, 'fr')` → `'1 234'`. Used for whole-unit labels (metres, yards,
/// feet) where the old code emitted an ungrouped `Math.round` string.
export function formatInteger(value: number, locale?: string): string {
	return formatLabel(formatter(locale, 0, 0), value);
}

/// A whole number with an explicit sign either side of zero — "+3", "-2",
/// "0" — for a balance such as training-stress balance, where a plain
/// `toFixed(0)` printed "-0" for -0.3 and the dashboard prefixed "+" onto a
/// value that then rounded to "0".
export function formatSignedInteger(value: number, locale?: string): string {
	if (!Number.isFinite(value)) return '—';
	const whole = Math.round(value);
	return (whole > 0 ? '+' : '') + formatInteger(whole, locale);
}

/// Intl prints NaN as "NaN", Infinity as "∞", and keeps the sign of a
/// negative that rounds to zero ("-0", "-0.0" for a training-stress balance
/// of -0.04). None is a number a runner can read, so a non-finite value is
/// the em dash and a negative zero loses its sign. Mirrors `formatFixed` in
/// apps/mobile_android/lib/l10n/number_format.dart.
function formatLabel(nf: Intl.NumberFormat, value: number): string {
	if (!Number.isFinite(value)) return '—';
	if (value < 0 || Object.is(value, -0)) {
		const zero = nf.format(0);
		if (nf.format(-value) === zero) return zero;
	}
	return nf.format(value);
}
