/// Stripe stores an amount in the currency's MINOR unit, and for a
/// zero-decimal currency the minor unit IS the base unit — a ¥1,000 donation
/// arrives as 1000, not 100000. A blanket `/ 100` understates those
/// currencies a hundredfold; a blanket `* 100` overstates them the same way
/// on the write side.
///
/// The authority is Stripe's own table (docs.stripe.com/currencies), not the
/// runtime's ISO 4217 data: ISO gives 0 decimals to COP, IDR, HUF, ISK, UGX
/// and others that Stripe takes as two-decimal, so asking `Intl` first put a
/// 50,000 COP price on the wire as 500.00 COP.
///
/// Dart twin: apps/mobile_android/lib/minor_units.dart, which the phone's event
/// price write uses (docs/architecture/parity_pairs.md); keep the two in lockstep.
const ZERO_DECIMAL_CURRENCIES = new Set([
	'BIF',
	'CLP',
	'DJF',
	'GNF',
	'JPY',
	'KMF',
	'KRW',
	'MGA',
	'PYG',
	'RWF',
	'VND',
	'VUV',
	'XAF',
	'XOF',
	'XPF'
]);

/// Stripe's two "special cases": zero-decimal currencies its API still takes
/// as two-decimal for backward compatibility, with the fraction always `00`
/// (5 ISK is `500`), and which cannot be charged in fractions.
const WHOLE_UNIT_TWO_DECIMAL_CURRENCIES = new Set(['ISK', 'UGX']);

const THREE_DECIMAL_CURRENCIES = new Set(['BHD', 'JOD', 'KWD', 'OMR', 'TND']);

const DEFAULT_FRACTION_DIGITS = 2;

function normalise(currency: string): string {
	return currency.trim().toUpperCase();
}

/// Digits of the minor unit Stripe's API counts `amount` in.
export function currencyFractionDigits(currency: string): number {
	const code = normalise(currency);
	if (ZERO_DECIMAL_CURRENCIES.has(code)) return 0;
	if (THREE_DECIMAL_CURRENCIES.has(code)) return 3;
	return DEFAULT_FRACTION_DIGITS;
}

export function fromMinorUnits(amountMinor: number, currency: string): number {
	return amountMinor / 10 ** currencyFractionDigits(currency);
}

export function toMinorUnits(amountMajor: number, currency: string): number {
	const digits = currencyFractionDigits(currency);
	const minor = Math.round(amountMajor * 10 ** digits);
	// Stripe rejects a three-decimal amount that is not a multiple of 10, and
	// an ISK / UGX amount that is not a whole unit (a multiple of 100).
	if (digits === 3) return Math.round(minor / 10) * 10;
	if (WHOLE_UNIT_TWO_DECIMAL_CURRENCIES.has(normalise(currency))) {
		return Math.round(minor / 100) * 100;
	}
	return minor;
}
