import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/single_flight.dart';

// Issue #1374 NS-11: a second tap during the read before a push opened a
// second copy of the screen.
void main() {
  test('a second open while the first resolves is dropped', () async {
    final flight = SingleFlight();
    final gate = Completer<void>();
    var opened = 0;
    final first = flight.openOnce(() async {
      await gate.future;
      opened++;
    });
    await flight.openOnce(() async => opened++);
    expect(flight.busy, isTrue);
    gate.complete();
    await first;
    expect(opened, 1);
    expect(flight.busy, isFalse);
  });

  test('a failed open frees the slot', () async {
    final flight = SingleFlight();
    await expectLater(
        flight.openOnce(() async => throw StateError('read failed')),
        throwsStateError);
    var opened = 0;
    await flight.openOnce(() async => opened++);
    expect(opened, 1);
  });
}
