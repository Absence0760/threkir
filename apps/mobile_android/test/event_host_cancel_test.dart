import 'package:flutter_test/flutter_test.dart';

import '../lib/event_host_cancel.dart';

Map<String, Object?> _summary({
  String outcome = 'complete',
  Object? initiated = 2,
  Object? failed = 0,
  Object? ids = const <String>[],
}) =>
    {
      'outcome': outcome,
      'initiated': initiated,
      'already_refunded': 1,
      'released': 0,
      'failed': failed,
      'failed_order_ids': ids,
    };

void main() {
  test('a complete summary decodes with its counts', () {
    final s = parseOccurrenceRefundSummary(_summary())!;
    expect(s.complete, isTrue);
    expect(s.refunded, 3);
    expect(s.failedOrderIds, isEmpty);
  });

  test('an incomplete summary names the orders still owed', () {
    final s = parseOccurrenceRefundSummary(
        _summary(outcome: 'incomplete', failed: 1, ids: ['o1']))!;
    expect(s.complete, isFalse);
    expect(s.failed, 1);
    expect(s.failedOrderIds, ['o1']);
  });

  test('a body that does not add up is refused, not read as success', () {
    for (final bad in <Object?>[
      null,
      'ok',
      _summary(outcome: 'done'),
      _summary(initiated: -1),
      _summary(initiated: 1.5),
      _summary(failed: 1, ids: const <String>[]),
      _summary(outcome: 'incomplete', failed: 0),
      _summary(outcome: 'complete', failed: 1, ids: ['o1']),
      _summary(ids: [1]),
    ]) {
      expect(parseOccurrenceRefundSummary(bad), isNull, reason: '$bad');
    }
  });

  test('the error code comes off the body, with a generic fallback', () {
    expect(eventCancelErrorCode({'error': 'stripe_not_configured'}),
        'stripe_not_configured');
    expect(eventCancelErrorCode({'error': ''}), 'cancel_failed');
    expect(eventCancelErrorCode('boom'), 'cancel_failed');
    expect(eventCancelErrorCode(null), 'cancel_failed');
  });
}
