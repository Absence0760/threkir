import 'l10n/gen/app_localizations.dart';
import 'typed_decimal.dart';

/// The paid-registration half of the phone's event form (club_events.md slice
/// P1), validated as web's `EventEditor` validates it: a price of at least
/// [eventPriceMinMajor] in a three-letter currency, a sales-close offset of
/// 0 to [eventSalesCloseMaxMinutes] minutes, and one of the refund policies
/// `event_pricing_refund_policy_check` allows.

/// `event_pricing.refund_policy`'s CHECK vocabulary, in the order the form
/// offers it.
const List<String> kEventRefundPolicies = [
  'full_until_start',
  'full_until_24h',
  'no_refund',
];

/// The default web's editor picks.
const String kDefaultEventRefundPolicy = 'full_until_24h';

String eventRefundPolicyLabel(AppLocalizations l10n, String policy) {
  switch (policy) {
    case 'full_until_start':
      return l10n.eventFormRefundFullUntilStart;
    case 'full_until_24h':
      return l10n.eventFormRefundFullUntil24h;
    case 'no_refund':
      return l10n.eventFormRefundNone;
    default:
      return policy;
  }
}

/// Web's price input carries `min="0.5"`.
const double eventPriceMinMajor = 0.5;

/// `event_pricing_sales_close_offset_minutes_check`'s ceiling: one week.
const int eventSalesCloseMaxMinutes = 10080;

/// Web's "end after N occurrences" input carries `max="520"`.
const int eventRecurrenceCountMax = 520;

/// An optional whole-number field: blank is `(value: null, ok: true)`; anything
/// else must be a whole number in [min, max].
({int? value, bool ok}) parseOptionalWhole(String raw, {required int min, int? max}) {
  final t = raw.trim();
  if (t.isEmpty) return (value: null, ok: true);
  final n = int.tryParse(t);
  if (n == null || n < min || (max != null && n > max)) {
    return (value: null, ok: false);
  }
  return (value: n, ok: true);
}

/// A price in major units, or null when it is not a number of at least
/// [eventPriceMinMajor]. Accepts the decimal comma a non-English keyboard types.
double? parseEventPrice(String raw) {
  final v = parseTypedDecimal(raw);
  if (v == null || !v.isFinite || v < eventPriceMinMajor) return null;
  return v;
}

/// A three-letter currency code, lowercased as `event_pricing.currency` stores
/// it, or null.
String? parseCurrencyCode(String raw) {
  final t = raw.trim();
  if (!RegExp(r'^[A-Za-z]{3}$').hasMatch(t)) return null;
  return t.toLowerCase();
}
