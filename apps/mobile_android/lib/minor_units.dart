/// Stripe stores an amount in the currency's MINOR unit, and for a
/// zero-decimal currency the minor unit IS the base unit — a ¥1,000 price is
/// 1000, not 100000. Dart twin of web's `apps/web/src/lib/format/minor_units.ts`
/// — keep the two in lockstep. The authority is Stripe's own table
/// (docs.stripe.com/currencies), not ISO 4217, which gives 0 decimals to
/// several currencies Stripe takes as two-decimal.
const _zeroDecimalCurrencies = {
  'BIF', 'CLP', 'DJF', 'GNF', 'JPY', 'KMF', 'KRW', 'MGA', //
  'PYG', 'RWF', 'VND', 'VUV', 'XAF', 'XOF', 'XPF',
};

/// Stripe's "special cases": zero-decimal currencies its API still takes as
/// two-decimal, with the fraction always `00`, and which cannot be charged in
/// fractions.
const _wholeUnitTwoDecimalCurrencies = {'ISK', 'UGX'};

const _threeDecimalCurrencies = {'BHD', 'JOD', 'KWD', 'OMR', 'TND'};

String _normalise(String currency) => currency.trim().toUpperCase();

/// Digits of the minor unit Stripe's API counts `amount` in.
int currencyFractionDigits(String currency) {
  final code = _normalise(currency);
  if (_zeroDecimalCurrencies.contains(code)) return 0;
  if (_threeDecimalCurrencies.contains(code)) return 3;
  return 2;
}

int _pow10(int digits) {
  var out = 1;
  for (var i = 0; i < digits; i++) {
    out *= 10;
  }
  return out;
}

double fromMinorUnits(int amountMinor, String currency) =>
    amountMinor / _pow10(currencyFractionDigits(currency));

int toMinorUnits(double amountMajor, String currency) {
  final digits = currencyFractionDigits(currency);
  final minor = (amountMajor * _pow10(digits)).round();
  // Stripe rejects a three-decimal amount that is not a multiple of 10, and an
  // ISK / UGX amount that is not a whole unit (a multiple of 100).
  if (digits == 3) return (minor / 10).round() * 10;
  if (_wholeUnitTwoDecimalCurrencies.contains(_normalise(currency))) {
    return (minor / 100).round() * 100;
  }
  return minor;
}
