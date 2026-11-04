// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

import '../lib/dm_pending_hides.dart';
import '../lib/monotonic_clock.dart';

void main() {
  final hides = DmPendingHides.instance;
  var now = Duration.zero;

  setUp(() {
    now = const Duration(seconds: 10);
    debugMonotonicNowOverride = () => now;
  });
  tearDown(() {
    debugMonotonicNowOverride = null;
    hides.debugClear();
  });

  test('a read started the instant a delete landed already carries it', () {
    // An open list holding an older read keeps the marker to be asked about.
    final reader = hides.reader();
    addTearDown(reader.close);
    reader.applied(const Duration(seconds: 5));
    hides.add('c-1');
    hides.landed('c-1');

    expect(hides.hides('c-1', now), isFalse);
    expect(hides.hides('c-1', now - const Duration(microseconds: 1)), isTrue);
  });

  test('a reset reader lets go of the landed marker it was keeping', () {
    final reader = hides.reader();
    addTearDown(reader.close);
    reader.applied(const Duration(seconds: 5));
    hides.add('c-1');
    hides.landed('c-1');
    expect(hides.debugHasMarker('c-1'), isTrue,
        reason: 'the read held started before the delete landed');

    reader.reset();
    expect(hides.debugHasMarker('c-1'), isFalse);
  });
}
