/// The organiser's side of calling off a club event from the phone: one
/// occurrence, a one-off event, or a whole recurring series (club_events.md
/// § Refunds & cancellation coupling, decisions § 1818 and § 1868). The
/// refunds themselves run in the `events-cancel` Edge Function; this file reads
/// what it answers.

/// The per-order summary `events-cancel` returns for a host cancel
/// (`summarizeOccurrenceRefunds` in `events-cancel/lib.ts`). Decoded with the
/// same rules as web's `parseOccurrenceRefundSummary`
/// (`apps/web/src/lib/social/paid_registration.ts`): a body that does not add
/// up is refused rather than read as a success.
class OccurrenceRefundSummary {
  /// `complete` only when no order is left holding money without a refund.
  final bool complete;
  final int initiated;
  final int alreadyRefunded;
  final int released;
  final int failed;
  final List<String> failedOrderIds;

  const OccurrenceRefundSummary({
    required this.complete,
    required this.initiated,
    required this.alreadyRefunded,
    required this.released,
    required this.failed,
    required this.failedOrderIds,
  });

  /// Registrants whose money is on its way back.
  int get refunded => initiated + alreadyRefunded;
}

OccurrenceRefundSummary? parseOccurrenceRefundSummary(Object? raw) {
  if (raw is! Map) return null;
  final outcome = raw['outcome'];
  if (outcome != 'complete' && outcome != 'incomplete') return null;
  final counts = <String, int>{};
  for (final k in const ['initiated', 'already_refunded', 'released', 'failed']) {
    final v = raw[k];
    if (v is! int || v < 0) return null;
    counts[k] = v;
  }
  final ids = raw['failed_order_ids'];
  if (ids is! List || ids.any((id) => id is! String)) return null;
  if (ids.length != counts['failed']) return null;
  if ((outcome == 'complete') != (counts['failed'] == 0)) return null;
  return OccurrenceRefundSummary(
    complete: outcome == 'complete',
    initiated: counts['initiated']!,
    alreadyRefunded: counts['already_refunded']!,
    released: counts['released']!,
    failed: counts['failed']!,
    failedOrderIds: ids.cast<String>(),
  );
}

/// A host cancel the function refused, carrying its machine `error` code
/// (`stripe_not_configured`, `not_event_organiser`, `not_a_series`, …) so the
/// screen can say which, rather than a generic failure.
class EventCancelRefused implements Exception {
  final String code;
  const EventCancelRefused(this.code);

  @override
  String toString() => 'EventCancelRefused($code)';
}

/// The machine code out of a non-2xx function response's body, or
/// `cancel_failed` when the body names none.
String eventCancelErrorCode(Object? details) {
  if (details is Map) {
    final code = details['error'];
    if (code is String && code.isNotEmpty) return code;
  }
  return 'cancel_failed';
}

/// The message `guard_paid_occurrence_cancel` (20270723000003) raises when a
/// client calls off an occurrence that still holds money.
const paidOccurrenceRefusal = 'paid_occurrence_requires_refund';
